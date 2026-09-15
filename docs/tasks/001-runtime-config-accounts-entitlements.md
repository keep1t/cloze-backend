# 001 — Runtime configuration, account settings, and entitlements

- Status: REVIEWED
- Source request/plan: Implement the Supabase backend from the Cloze V1 architecture and PRD through the Cloze pipeline.
- Dependencies and evidence they are ready: repository harness is present; local Supabase is running; CLI 2.105.0 and PostgreSQL 17 configuration were verified.
- Developer: initial implementation was assigned to `gpt-5.6-luna` at medium as the verified lower-cost model. Its quota was exhausted after partial scoped work; the coordinator completed the unchanged READY scope directly. Independent review approved the final artifact.
- Global assignment correction round: 1

## Outcome and boundaries

- Expected behavior (before → after): no product data model → validated runtime configuration, owner-scoped account settings, and private server-managed entitlements.
- Out of scope: purchase-provider webhooks, subscription reconciliation, provider console provisioning, garment data, recommendations, weather, embeddings, sharing, and seeded business limits.
- Permitted files: `supabase/migrations/20260915165103_runtime_config_accounts_entitlements.sql`, `supabase/tests/database/runtime_config_accounts_entitlements.test.sql`, `docs/auth-provider-setup.md`, `README.md`, `MEMORY.md`, and this record.
- Proposed new files: every permitted path except the existing README and memory.

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols: `supabase/config.toml` disables automatic Data API exposure, exposes only `public`/`graphql_public`, uses PostgreSQL 17, and has disabled Apple Auth configuration; no product migrations or tests existed. `Makefile` exposes `make test-db`, `make check`, and guarded local reset commands.
- Verified contracts/documentation/API and version: Supabase CLI 2.105.0; current Supabase RLS guidance requires grants and RLS independently, owner checks with `(select auth.uid())`, and `USING` plus `WITH CHECK` for updates. Hosted OAuth provider configuration is operational state, not a SQL migration.
- Relevant external product requirements: Eraser architecture and Cloze V1 PRD require Apple/Google Auth with explicit linking, `auth.uid()` ownership, privacy settings, server-validated entitlements, no PII copies, and externally configured Free/Premium limits.
- Verified assumptions; open decisions (none for READY): purchase-provider integration is explicitly deferred. Configuration keys are contractual names; values are environment-managed data and are not seeded by this task.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - `private.product_config(key text primary key, value jsonb not null, updated_at timestamptz not null)` stores managed configuration without migration-seeded business values.
  - `private.get_config_integer(p_key text, p_min bigint, p_max bigint) returns bigint`, `private.get_config_text(p_key text) returns text`, and `private.get_config_text_array(p_key text) returns text[]` provide typed reads. Missing keys, wrong JSON types, non-integral numbers, or out-of-range values raise a stable `CONFIGURATION_ERROR` marker without exposing values.
  - `public.user_settings` uses `user_id uuid` as PK/FK to `auth.users(id)`, JSON preferences/privacy documents, their positive schema versions, and timestamps. JSON values must be objects.
  - `private.user_entitlements` uses owner UUID, entitlement key, `active|inactive|revoked` status, validity timestamps, optional opaque source reference, and timestamps. `valid_until`, when present, must be after `valid_from`.
- Outputs/errors and edge-case behavior:
  - `private.has_active_entitlement(p_user_id uuid, p_entitlement_key text, p_at timestamptz) returns boolean` returns true only for `active` records whose inclusive start and exclusive end contain the caller-supplied instant. It is service-role/internal only; the Edge layer must derive `p_user_id` from its verified JWT.
  - `private.handle_new_user() returns trigger` inserts only the new Auth UUID and empty JSON objects; it never copies email or metadata.
  - Configuration validation fails closed with SQLSTATE `P0001` and a message containing only `CONFIGURATION_ERROR` plus the key name.
- Authorization/RLS/privacy and required configuration:
  - `private` is not exposed. Revoke schema/table/function access from `PUBLIC`, `anon`, and `authenticated`; grant only the minimum required to `service_role`.
  - Enable and force RLS on both product tables. `user_settings` grants only select/insert/update/delete to `authenticated`, with owner policies based on `(select auth.uid()) = user_id`. Entitlements/config have no client policies.
  - Do not use `user_metadata`, copy PII, or seed limits, TTLs, prices, timezones, provider IDs, or secrets.
  - Document these required managed keys without values: `limits.free.active_garments`, `limits.free.daily_recommendations`, `recommendations.daily_reset_timezone`, `sharing.default_ttl_days`, `sharing.renewal_days`, `sharing.upload_ttl_seconds`, `sharing.max_snapshot_bytes`, `sharing.allowed_mime_types`.
  - Document manual Apple/Google provider setup, explicit identity linking, redirect allowlisting, secret handling, and accepting any successful 2xx OAuth token response.
- Test specifications (for product code): `supabase/tests/database/runtime_config_accounts_entitlements.test.sql` must cover schema/grants/RLS, owner and non-owner CRUD, owner reassignment rejection, anonymous denial, configuration validation, entitlement time boundaries, and the Auth trigger's PII minimization.
- Test author output and coordinator-verified failing command/output (required before READY): `supabase/tests/database/runtime_config_accounts_entitlements.test.sql` was written before production implementation. On 2026-09-15, `make test-db` failed as expected because `public.user_settings` and the other specified product objects did not exist; pgTAP reported the first 12 contract checks failed and exited non-zero before later behavioral assertions. This is the recorded red baseline.
- Concrete ordered steps:
  1. Test author writes only the specified pgTAP file.
  2. Coordinator runs it against the unchanged schema and records the expected missing-object failure.
  3. Coordinator marks this record READY.
  4. Developer implements the migration and documentation without changing the tests.
  5. Developer runs database tests and repository checks, then records evidence here and in README/memory.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Account settings are isolated by owner and cannot be reassigned. | `make test-db` with local stack | Owner CRUD passes; cross-owner and anonymous operations are denied. |
| AC2 | Runtime configuration fails closed. | `make test-db` | Missing, wrongly typed, non-integral, and out-of-range values raise `CONFIGURATION_ERROR`. |
| AC3 | Entitlements are private and time-bounded. | `make test-db` | Clients cannot access them and the private predicate observes validity boundaries. |
| AC4 | Auth provisioning stores no copied PII. | `make test-db` | Trigger-created settings contain only UUID, empty JSON documents, versions, and timestamps. |
| AC5 | Least-privilege grants and RLS are complete. | `make test-db` and `supabase db lint --local --level warning --fail-on warning` | Required policies/grants exist with no public/anon access. |
| AC6 | Tests were red before implementation and green afterward. | Recorded baseline plus `make test-db` | Coordinator evidence shows expected pre-implementation failure and final pass. |
| AC7 | Project documentation and quality gates reflect the implementation. | `make check` | README, memory, OAuth setup, formatting, lint, type checks, harness, and security gate pass. |

## Stop conditions

- Missing information, code mismatch, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: AC1–AC6 passed through `make test-db` (80 pgTAP checks), `supabase db lint --local --level warning --fail-on warning`, and `supabase db advisors --local`; AC7 passed through `make check` (security gate, format/lint/typecheck, and 40 harness tests). The red baseline is recorded above. No remote configuration, deployment, or commit was run.
- Changed files and MEMORY/README update: migration, pgTAP contract test, Auth provider setup guide, README, MEMORY.md, and this task record.
- Test results: the test-author's initial contract failed on missing objects; it later passed all 76 tests. Correction R1 added three timestamp regressions, which failed before the trigger implementation and passed after it; the final suite has 80 passing tests.
- Outstanding work and review findings with IDs: R1 (stale `updated_at`) was resolved with a private pinned-path trigger function and three before-update triggers. No remaining technical review findings.
- Technical review status: APPROVED after correction round 1; reviewer independently reran the database suite, lint, advisors, `make check`, and diff check.
- Human review/commit: pending; no commit is authorized.
