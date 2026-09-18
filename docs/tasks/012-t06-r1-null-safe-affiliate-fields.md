# 012 — Reject missing required affiliate fields with `P0001`

- Status: REVIEWED (APPROVED)
- Source request/plan: User-authorized atomic task resolving T06 reviewer finding R1.
- Dependencies and evidence they are ready: The T06 migration and pgTAP suite exist;
  T03/T04 contracts are unchanged. This task resolves T06 R1.
- Developer: OpenCode `cloze-developer` uses `opencode/big-pickle` without a variant.
  The coordinator reconfirmed its active status, tool-call capability, and zero-cost
  metadata with `opencode models opencode --verbose` before delegation.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before -> after): A two-key affiliate object that omits either
  required field currently reaches a later `23502` constraint error. It must instead
  deterministically raise `P0001` before any persistence side effect.
- Out of scope: Any other T06 validation, replay, collision, RLS, grants, schema,
  function signature, migration architecture, configuration, endpoint, or T03/T04
  change. Do not create a new migration.
- Permitted files:
  - `supabase/migrations/20260916135232_share_operation_affiliate_persistence.sql`
  - `supabase/tests/database/share_operation_affiliate_persistence.test.sql`
  - `docs/tasks/006-share-operation-affiliate-persistence.md`
  - `docs/tasks/012-t06-r1-null-safe-affiliate-fields.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files: None.

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols:
  - `supabase/migrations/20260916135232_share_operation_affiliate_persistence.sql`:
    T06 function with the R1 predicates.
  - `supabase/tests/database/share_operation_affiliate_persistence.test.sql`: T06
    pgTAP contract suite.
  - `docs/tasks/006-share-operation-affiliate-persistence.md`: historical T06
    contract and blocking review finding.
- Verified contracts/documentation/API and version: PostgreSQL/Supabase migrations and
  pgTAP conventions already used by T06. This SQL-only task adds no dependency.
- Relevant external product requirements: Not applicable. This is a bounded correction
  to an accepted in-repository contract.
- Resolved decisions: Missing JSON keys evaluate to SQL NULL, so `is distinct from
  'string'` is required for deterministic field validation. The T06 migration is
  corrected in place.

## Implementation contract

- `private.create_share_operation(...)` remains service-role-only, `SECURITY INVOKER`,
  and `search_path = ''`.
- An affiliate element remains an object with exactly two keys. Its `garment_ref` and
  `url` values must each be JSON strings.
- Replace only these predicates with null-safe equivalents:
  - `jsonb_typeof(v_link -> 'garment_ref') is distinct from 'string'`
  - `jsonb_typeof(v_link -> 'url') is distinct from 'string'`
- Either required field missing raises `P0001` before advisory locking or inserts, and
  creates no snapshot, operation, affiliate-link, or cleanup row.
- Authorization, RLS, grants, privacy boundaries, and persisted data do not change.
- Test specifications: The restricted test author modifies only
  `supabase/tests/database/share_operation_affiliate_persistence.test.sql` with two
  `throws_ok` cases for exact two-key objects missing each required field and one
  no-side-effect postcondition. Verification: `make test-db`.
- Test author output and coordinator-verified failing command/output: The restricted
  test author added the two missing-key cases and no-side-effect assertion without
  running commands. The coordinator reset the disposable local database with
  `supabase db reset --local --yes` after the Make wrapper failed during initialization,
  then ran `make test-db` against the unchanged migration. The T06 suite failed exactly
  at tests 46 and 47: each caught `23502` and expected `P0001`; the other four suites
  passed. This task is READY.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Missing `url` raises `P0001`, not `23502` | New pgTAP case after fresh local reset | `throws_ok` passes |
| AC2 | Missing `garment_ref` raises `P0001`, not `23502` | New pgTAP case after fresh local reset | `throws_ok` passes |
| AC3 | Both rejected inputs have no side effects | New pgTAP postcondition | Zero related rows |
| AC4 | Only the two null-safe predicates change; existing behavior remains covered | Migration diff and complete `make test-db` | No scope expansion; all tests pass |
| AC5 | Tests fail before and pass after implementation | Coordinator baseline, then `make test-db` | Baseline mismatch recorded; final pass |
| AC6 | Rebuilt local schema and repository checks are clean | `make check-all CONFIRM_RESET=cloze-backend`, `git diff --check` | Commands pass |
| AC7 | Documentation reflects T012 and T06 status without premature approval claims | Review permitted documentation | Accurate state |

## Stop conditions

- If the current T06 migration/test does not contain the stated R1 predicates, the
  baseline does not reproduce the SQLSTATE mismatch, or any change outside this scope
  is required: return `NEEDS_CLARIFICATION` with evidence.
- Two failed implementation attempts for the same cause: return `BLOCKED` with what
  was tried.
- Do not commit, deploy, or alter files outside the permitted list.

## Delivery (complete after implementation)

- Status: REVIEWED (independent technical review APPROVED).
- Criteria met and actual evidence, commands/results, and checks not run:
  - AC1, AC2, AC3: with the corrected migration applied on a fresh local reset,
    T06 pgTAP tests 46 and 47 (exact two-key affiliate objects missing `url` and
    `garment_ref`, respectively) raise `P0001`, and the no-side-effect
    postcondition confirms zero snapshot, operation, affiliate, and cleanup rows.
  - AC4: the migration diff contains only the two null-safe predicate changes:
    `jsonb_typeof(v_link->'garment_ref') is distinct from 'string'` and the
    equivalent `url` check. No test file changed after the coordinator baseline;
    the restricted test author's cases existed before the task became READY.
  - AC5: coordinator-verified baseline: after the unchanged migration and a
    direct local reset, `make test-db` failed exactly at T06 tests 46 and 47,
    each catching `23502` and expecting `P0001`; the other four suites passed.
    The final run passes (see below).
  - AC6: coordinator `make check-all CONFIRM_RESET=cloze-backend` PASSED: all
    six migrations applied; `supabase db lint` reported no schema errors; 5 pgTAP
    files / 332 tests passed; 8 function tests passed; 40 harness tests passed;
    the generated-types check was explicitly skipped because
    `supabase/functions/_shared/database.types.ts` does not exist. `git diff
    --check` passed after the predicate edit. The developer then re-ran the
    permitted component checks on the same reset database with identical
    results: `make db-lint` (no schema errors), `make test-db` (Files=5,
    Tests=332, Result: PASS), `make test-functions` (8 passed), `make
    types-check` (skipped: file absent), `git diff --check` (clean).
  - Checks not run by the developer: the aggregate `make db-reset` and `make
    check-all` commands are hard-denied for the `cloze-developer` permission in
    `opencode.json`; the coordinator ran the reset and `make check-all`, and the
    developer ran the equivalent component checks above and reported the
    deviation precisely.
- Changed files and MEMORY/README update:
  - `supabase/migrations/20260916135232_share_operation_affiliate_persistence.sql`
    (two predicates only, around lines 152-153).
  - `supabase/tests/database/share_operation_affiliate_persistence.test.sql`
    (restricted test author; T012 cases 46-48 existed before implementation and
    were not edited by the developer).
  - `docs/tasks/006-share-operation-affiliate-persistence.md`
  - `docs/tasks/012-t06-r1-null-safe-affiliate-fields.md`
  - `MEMORY.md`
  - `README.md`
- Test results, including the preimplementation failure and final pass:
  - Preimplementation (coordinator, unchanged migration, direct local reset):
    `make test-db` failed at T06 tests 46 and 47 (caught `23502`, expected
    `P0001`); the other four suites passed.
  - Final: coordinator `make check-all CONFIRM_RESET=cloze-backend` PASSED (5
    pgTAP files / 332 tests, 8 function tests, 40 harness tests, no schema lint
    errors); developer component re-run: `make test-db` → Files=5, Tests=332,
    Result: PASS; `make test-functions` → 8 passed.
- Outstanding work and review findings with IDs: R1 is resolved. Independent
  technical review APPROVED with no findings; no other findings are open. Local
  `supabase start` output during `make check-all` printed local
  DB/API/Storage credential values; no publication is authorized and local
  credential rotation/recreation is required before publication. No credential
  values are recorded in this repository.
- Technical review status: APPROVED. This technical approval does not authorize a
  commit, push, deployment, or publication.
- Human review/commit: The R1 resolution is recorded in commit `da40515`, authored
  by Alian. No deployment or publication authorization is recorded.
