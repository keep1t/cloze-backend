# 011 — Deactivate expired shares and physically clean private snapshots

- Status: PENDING
- Source request/plan: Complete the Supabase-owned expiry and deletion lifecycle for Eraser V1 shares.
- Dependencies and evidence they are ready: Tasks 006 and 010 must be IMPLEMENTED and reviewed; T04's deadline semantics must remain valid.
- Developer: Unassigned pending coordinator verification of an available cost-effective model and environment. Do not assume model availability.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, expiry prevents resolution but leaves remote objects and failed revocation deletions behind. After, a protected scheduled cleanup worker claims bounded batches, makes expired shares durably inactive, deletes expired/revoked/stale-pending objects, and records retry-safe completion.
- Out of scope: Share renewal, account deletion, source garment images, landing UI, analytics, and arbitrary Storage garbage collection.
- Permitted files:
  - One new imperative migration under `supabase/migrations/`, generated with `supabase migration new share_snapshot_cleanup_claims`
  - `supabase/functions/share-cleanup/**`
  - Necessary cleanup files under `supabase/functions/_shared/**`
  - A deployment-safe Cron configuration/runbook file if the repository's verified convention requires it
  - `supabase/tests/database/share_snapshot_cleanup_test.sql`
  - `supabase/tests/functions/share-cleanup_test.ts`
  - `docs/tasks/011-clean-expired-share-snapshots.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files:
  - Timestamped cleanup-claim migration
  - `supabase/functions/share-cleanup/index.ts`
  - `supabase/functions/share-cleanup/deno.json`
  - Cleanup use case, ports, and adapters
  - `supabase/tests/database/share_snapshot_cleanup_test.sql`
  - `supabase/tests/functions/share-cleanup_test.ts`

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: T04 deadlines/revocation, task 006 cleanup bookkeeping, task 010 immediate deletion/retry handoff, and T05 architecture.
- Verified contracts/documentation/API and version:
  - [Supabase Cron](https://supabase.com/docs/guides/cron) supports database jobs and Edge invocation.
  - [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
  - The project's supported Cron/Vault invocation pattern and pinned function dependencies must be verified before implementation.
- Relevant external product requirements: NF2 requires this temporary remote snapshot exception to remain narrow; Eraser specifies deletion on owner revocation or 15-day expiry.
- Verified assumptions; open decisions:
  - Required configuration: cleanup batch size, claim lease duration, stale-pending lifetime, retry policy, and schedule. No code defaults are allowed.
  - Before READY, operations/product must explicitly choose those values. The active share TTL remains the configured 15-day value from task 007.
  - Cron credentials must be held in Supabase Vault or another verified server-only facility, never migration literals or client configuration.
  - If the repository lacks a secret-safe reproducible scheduling convention, this task remains PENDING/NEEDS_CLARIFICATION while the worker and database claim mechanism may be split into a separate task.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - Protected scheduled invocation with no business payload; an optional test-only/internal batch override must not be exposed in production.
  - Clock, batch limit, lease interval, and retry decision are explicit injected inputs.
  - Candidate classes: expired active shares, revoked shares with undeleted objects, and pending shares older than the configured stale-pending lifetime.
- Outputs/errors and edge-case behavior:
  - Internal summary only: `{ claimed, deleted, alreadyMissing, retryPending, failed }`, with no paths, tokens, or owner IDs.
  - Claiming uses bounded concurrency-safe semantics such as `FOR UPDATE SKIP LOCKED` in a private function.
  - Expired active shares are made inactive before deletion.
  - Missing objects count as successful deletion.
  - Transient delete failures release or expire their lease for retry; terminal bookkeeping remains bounded and contains no provider body.
  - A failed item does not reactivate shares or block unrelated candidates.
- Authorization/RLS/privacy and required configuration:
  - The endpoint accepts only verified scheduler/service authorization.
  - Private claim/complete/fail functions have pinned `search_path`, public execute revoked, and service-only grants.
  - Cron URL and credentials are server-only; no secret values may appear in repository files, migration literals, logs, or responses.
  - The worker deletes only canonical paths obtained from claimed private records.
  - Scheduling uses validated configured values and a documented provisioning step.
- Test specifications (for product code):
  - Database test path: `supabase/tests/database/share_snapshot_cleanup_test.sql`; cover eligible/ineligible states, expiration boundary, lease exclusivity, lease recovery, bounded batches, success/failure transitions, grants, and pinned security context.
  - Function test path: `supabase/tests/functions/share-cleanup_test.ts`; cover authorization, delete success, already absent, transient failure, mixed-batch continuation, canonical paths only, injected time/config, and redaction.
  - Verification commands: `make test-db` and `make test-functions`.
- Test author output and coordinator-verified failing command/output (required before READY): Pending for both test files and both baseline failures.
- Concrete ordered steps:
  1. Decide and record the schedule, batch, lease, stale-pending, and retry configuration.
  2. Verify a secret-safe Supabase Cron/Vault deployment pattern.
  3. Add failing SQL and Deno tests; record both baselines.
  4. Generate the migration and add private claim/complete/fail functions.
  5. Implement cleanup use case, adapters, and protected handler.
  6. Add reproducible secret-safe schedule configuration or its reviewed operational runbook.
  7. Verify concurrent workers and mixed failure batches.
  8. Update evidence, `MEMORY.md`, and `README.md`.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Expired shares become inactive before deletion | SQL and ordered fake tests | Resolver cannot race into serving an expired candidate |
| AC2 | Revoked/stale-pending objects are deleted | Function tests | Only eligible canonical objects are targeted |
| AC3 | Concurrent runs do not duplicate claims | pgTAP concurrency/lease tests | A candidate has one active lease |
| AC4 | Failures retry safely | Mixed-batch tests | Failed item remains eligible and others complete |
| AC5 | Missing objects complete cleanup | Storage fake test | `object_deleted_at` is recorded |
| AC6 | Scheduler is protected and secret-safe | Config/runbook inspection plus auth test | Unauthorized calls fail and no credentials are literal |
| AC7 | Work is bounded by configuration | Batch/config tests | No unbounded scan or hardcoded business value |
| AC8 | Local-first boundary closes after expiry | End-to-end lifecycle test | Remote composite becomes inaccessible and is physically removed |

## Stop conditions

- No approved cleanup configuration, no secret-safe scheduler pattern, a schema mismatch, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: Pending.
- Changed files and MEMORY/README update: Pending.
- Test results, including both preimplementation failures and final passes: Pending.
- Outstanding work and review findings with IDs: Pending.
- Technical review status: Pending.
- Human review/commit: Pending; record only actual human authorization.

