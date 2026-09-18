# 013 — Atomically begin or replay a share operation with expected upload metadata

- Status: NEEDS_CLARIFICATION — reset, lint, and all 363 pgTAP checks pass; AC8 remains unverified because the live local runner opens both `psql` sessions but waits indefinitely for a phase marker.
- Source request/plan: User-approved prerequisite for T007: persist declared snapshot upload metadata and make an authenticated operation replayable without recomputing time-bound values.
- Dependencies and evidence they are ready: T04 private snapshot lifecycle and T06 operation/affiliate/cleanup persistence are REVIEWED; T012 resolved T06 validation R1. T06 is recorded in `bdda2ec` and `da40515`.
- Developer: Codex `gpt-5.6-luna` at medium reasoning, verified available in the current delegation environment; selected by the repository's required cost-effective model policy.
- Global assignment correction round: 1 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, T06 can replay only identical caller-supplied deadlines and stores no declared content type or length; a later retry conflicts and later confirmation cannot verify expected object metadata. After, one service-only SQL call atomically creates a new operation plus immutable expected upload metadata, or returns the original contract for an exact same-owner operation regardless of new candidate IDs and times; terminal operations never create replacements.
- Out of scope: Edge functions, JWT verification, HMAC generation or key loading, URL parsing/allowlisting/normalization, signed upload issuance, configuration value selection, upload bytes, object metadata inspection/activation, public resolution, revocation/deletion/cleanup scheduling, changes to T04 lifecycle semantics, and cloud outfit/garment/image/source data.
- Permitted files:
  - One new imperative migration under `supabase/migrations/`, created with `make migration NAME=share_operation_begin_upload_contract`.
  - `supabase/tests/database/share_operation_affiliate_persistence.test.sql`.
  - `supabase/tests/database/concurrency/share_operation_begin_replay.json`.
  - `docs/tasks/013-share-operation-begin-upload-contract.md`.
  - `MEMORY.md`.
  - `README.md`.
- Proposed new files: the timestamped migration only.

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, `README.md`, `docs/development-workflow.md`, `docs/atomic-tasks.md`, and the task template.
- Relevant paths/symbols:
  - `supabase/migrations/20260915191819_private_share_snapshots.sql`: `private.share_snapshots`, canonical private path, state/deadline rules, and lifecycle functions.
  - `supabase/migrations/20260916135232_share_operation_affiliate_persistence.sql`: T06 private operation, affiliate and cleanup persistence plus service-only `private.create_share_operation` and its advisory-lock key.
  - `supabase/tests/database/share_operation_affiliate_persistence.test.sql`: existing service-only/RLS, structural, replay, and no-prohibited-persistence pgTAP conventions.
  - `docs/tasks/006-share-operation-affiliate-persistence.md` and `docs/tasks/012-t06-r1-null-safe-affiliate-fields.md`: accepted T06/T012 contracts, including null-safe affiliate validation.
- Verified contracts/documentation/API and version: PostgreSQL 17/Supabase imperative migrations; existing private-schema RLS/grant and `SECURITY INVOKER SET search_path=''` convention. T013 uses no external API/package/configuration.
- Relevant product requirements: approved temporary composite snapshot exception under F3.3–F3.4 and NF2/NF4; source garment images, closet data, PII, cloud outfit/garment records, raw tokens, and object paths remain prohibited.
- Resolved decisions:
  - Expected snapshot `content_type` and `byte_length` are immutable private upload-contract metadata, not image data.
  - Replay compares only stable client values: owner/operation, ordered affiliates, content type, and byte length. It never compares regenerated share ID/token hash/key version or server times/deadlines.
  - Pending shares at or after their upload deadline return `upload_window_expired`; active expired shares return `share_expired`; revoked shares return `share_revoked`; all require a new `operation_id`.
  - A pre-T013 T06 operation without an upload-contract row returns `unavailable`, without backfilling replay input.
  - T007 owns HTTPS normalization and configured MIME/size/host limits.

## Implementation contract

### Private persistence

Create exactly this private table:

```sql
private.share_snapshot_upload_contract (
  share_id uuid primary key references private.share_snapshots(share_id) on delete cascade,
  expected_content_type text not null check (
    expected_content_type = trim(expected_content_type)
    and length(expected_content_type) > 0
  ),
  expected_byte_length bigint not null check (expected_byte_length > 0)
)
```

- Enable and force RLS, create no policies, revoke all table privileges from `PUBLIC`, `anon`, `authenticated`, `service_role`, and `current_user`, then grant only CRUD to `service_role`.
- Do not add timestamps, object names/paths, raw token/hash duplicates, image/blob/content, original request body, owner copy, garment/outfit record, PII, provider body, configuration, or a client Storage policy.

### Atomic service API

```sql
private.begin_share_operation(
  p_owner_id uuid,
  p_operation_id uuid,
  p_share_id uuid,
  p_token_hash bytea,
  p_token_key_version text,
  p_upload_expires_at timestamptz,
  p_expires_at timestamptz,
  p_expected_content_type text,
  p_expected_byte_length bigint,
  p_affiliate_links jsonb,
  p_now timestamptz
) returns table (
  decision text,
  share_id uuid,
  token_key_version text,
  status text,
  upload_expires_at timestamptz,
  expires_at timestamptz,
  expected_content_type text,
  expected_byte_length bigint
)
```

- The function is `SECURITY INVOKER` with `search_path = ''`; revoke default execution from `PUBLIC`, `anon`, `authenticated`, and `service_role`, then grant execution only to `service_role`.
- Before locks or inserts, validate all required arguments: no NULL UUID/time/json/hash/key/version/metadata; nonempty hash; trimmed nonempty key version/content type; positive byte length; valid deadline ordering; and the exact T06 affiliate-array structure. Invalid input raises `P0001` with no side effect.
- Acquire T06's transaction-scoped advisory lock using `p_owner_id || ':' || p_operation_id` before reading the operation.
- For an existing same-owner operation, join operation, snapshot, ordered affiliates, and upload contract:
  - If no upload-contract row exists, return `unavailable` with every other result column NULL, without mutation.
  - If affiliates, content type, or byte length differ, return non-disclosing `conflict` with every other result column NULL, without mutation.
  - `pending` before upload deadline returns `pending_replay` and stored fields; at/after deadline returns `upload_window_expired` with other fields NULL.
  - `active` before share expiry returns `active_replay` and stored fields; at/after expiry returns `share_expired` with other fields NULL.
  - `revoked` returns `share_revoked` with other fields NULL. An unrecognized status aborts as a corrupted invariant.
- Existing operations ignore all candidate share/token/key/deadline fields after structural validation. T007 regenerates its token using the returned stored key version; replay never replaces server-created state.
- With no existing operation, call T06 `private.create_share_operation`. On `created`, insert exactly one upload-contract row in the same transaction and return `created` with the stored creation contract. On `conflict`, return non-disclosing `conflict`; an unexpected decision/error rolls back.
- Do not alter T06 signatures, its RLS/ACL behavior, or its existing tables. T013 becomes T007's caller-facing begin/replay API.

## Test specification

- Restricted test-author paths: `supabase/tests/database/share_operation_affiliate_persistence.test.sql` and `supabase/tests/database/concurrency/share_operation_begin_replay.json`.
- Verification command: `make test-db`.
- The test author must add before implementation:
  1. New-table schema/keys/constraints, private RLS/grants, and prohibited-field checks.
  2. Exact service-function signature/hardening plus anon/authenticated denials.
  3. Atomic first creation of all T04/T06/T013 state.
  4. Same owner/operation at a later clock with changed candidate ID/hash/key/deadlines returns original `pending_replay` without mutation.
  5. Active replay and each terminal decision, with no replacement or data disclosure for terminal outcomes.
  6. Affiliate/content-type/byte-length conflicts, cross-owner isolation, unrelated collisions, and legacy T06-only `unavailable` handling.
  7. NULL, blank, nonpositive, deadline, malformed affiliate, integer/boolean, and missing-key validation cases that raise `P0001` without side effects.
  8. Two-session concurrency manifest: one creation, a generated advisory-lock probe returning false, then one replay after release. Use T014's fixed manifest schema and local-only runner.
- Test-author output: `supabase/tests/database/share_operation_affiliate_persistence.test.sql` covers AC1–AC7 and AC9–AC10. The T014-reviewed runner now supplies the AC8 facility; the test author must add its T013 manifest before READY and runs no commands.
- Coordinator baseline: on the unchanged six-migration schema, `make test-db` failed as expected in the T013 suite: tests 62–63 report the absent `private.share_snapshot_upload_contract`, then the catalog assertion raises `relation "private.share_snapshot_upload_contract" does not exist` (exit 1). The other four database suites passed. With the test-author manifest present, `make test-db-concurrency` also failed as expected with the runner's sanitized `Database concurrency tests failed; diagnostics were suppressed` outcome because T013's function/schema does not exist. These failures establish the test-first baseline.

## Criteria and verification

| ID | Observable criterion | Method | Expected result |
| --- | --- | --- | --- |
| AC1 | Upload contract is private and minimal | pgTAP via `make test-db` | Service-role CRUD only; no prohibited fields |
| AC2 | First begin is atomic | pgTAP creation/rollback tests | All T04/T06/T013 state exists once, or none exists |
| AC3 | Later retry replays original contract | pgTAP later-clock/candidate-change test | `pending_replay`, no deadline-derived conflict |
| AC4 | Stable client content is immutable | pgTAP affiliate/metadata conflicts | Non-disclosing conflict, no mutation |
| AC5 | Terminal states cannot renew the same operation | pgTAP lifecycle cases | Defined terminal decisions, no replacement |
| AC6 | Isolation, collisions, and legacy state fail closed | pgTAP isolation/collision/legacy cases | No other-owner data leak or backfill |
| AC7 | Function is hardened and input failure has no effects | pgTAP validation/privilege tests | Service-only; `P0001` before mutation |
| AC8 | Concurrent calls create once | Two-session pgTAP test | One creation and one replay |
| AC9 | Tests are test-first and pass after implementation | Recorded baseline, then `make test-db` | Missing-object baseline and final pass |
| AC10 | Documentation and scope are accurate | `git diff --check`; independent review | Only permitted scope changes |

## Stop conditions

- If the T04/T06 signatures or lock expression differ, the suite cannot support an approved two-session test, a persisted status is incompatible, or the change needs Edge/config/Storage behavior: return `NEEDS_CLARIFICATION` with evidence.
- After two failed attempts for the same cause, return `BLOCKED` with evidence.
- Do not commit, deploy, push, use production credentials, or change files outside the permitted scope.

## Delivery

The migration is created; local reset, `make db-lint`, and `make test-db` pass (5
suites / 363 checks). Host `psql` is installed, T016 permits the strictly empty
synthetic Auth fixture, and the live runner advances through validation to both
sessions. AC8 is nevertheless unverified: the runner then waits indefinitely for its
phase marker. That runner-protocol correction is outside T013 scope. No commit,
deployment, or publication is authorized.
