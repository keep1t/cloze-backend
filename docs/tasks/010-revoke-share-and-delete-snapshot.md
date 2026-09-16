# 010 — Revoke an owned share and remove its remote snapshot

- Status: PENDING
- Source request/plan: Implement owner revocation for the Supabase portion of the Eraser V1 sharing architecture.
- Dependencies and evidence they are ready: Tasks 006 and 007 must be IMPLEMENTED and reviewed; T04's revoke primitive must remain valid.
- Developer: Unassigned pending coordinator verification of an available cost-effective model and environment. Do not assume model availability.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, only a private SQL revocation primitive exists. After, the authenticated owner can revoke a share, immediately making its token unusable and attempting physical deletion of the private snapshot; failed deletion is durably handed to cleanup.
- Out of scope: Public resolution, renewal, app UI, bulk account deletion, and scheduled expiry cleanup.
- Permitted files:
  - `supabase/functions/share-revoke/**`
  - Necessary revoke files under `supabase/functions/_shared/**`
  - `supabase/config.toml` if needed
  - `supabase/tests/functions/share-revoke_test.ts`
  - `docs/tasks/010-revoke-share-and-delete-snapshot.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files:
  - `supabase/functions/share-revoke/index.ts`
  - `supabase/functions/share-revoke/deno.json`
  - Revocation use case and ports/adapters
  - `supabase/tests/functions/share-revoke_test.ts`

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: T04's revoke function, task 006 operation lookup/cleanup state, and T05 boundaries.
- Verified contracts/documentation/API and version:
  - [Supabase Edge authentication](https://supabase.com/docs/guides/functions/auth)
  - [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
  - Dependencies must be verified and pinned before implementation.
- Relevant external product requirements: NF2's narrow temporary-snapshot exception requires physical removal when sharing ends.
- Verified assumptions; open decisions:
  - Revocation identifies the share by `operationId`, avoiding client authority over owner/path.
  - Database revocation occurs before Storage deletion so the token becomes unusable even if provider deletion fails.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - `POST /functions/v1/share-revoke`
  - Required user JWT plus `{ "operationId": "<uuid>" }`.
- Outputs/errors and edge-case behavior:
  - `200 { status: "revoked", objectDeleted: true }` when deletion is complete or the object is already absent.
  - `202 { status: "revoked", objectDeleted: false, cleanupPending: true }` when logical revocation succeeds but Storage deletion fails.
  - Repeated requests are idempotent.
  - Another user receives a non-enumerating `404`.
  - Revocation never reactivates or extends a share.
- Authorization/RLS/privacy and required configuration:
  - JWT subject must match the operation owner; ignore client owner/path.
  - Service credentials remain adapter-only.
  - Record bounded error codes and attempt metadata, never provider bodies, signed URLs, or secrets.
  - Revocation commits before physical deletion is attempted.
- Test specifications (for product code):
  - Test author path: `supabase/tests/functions/share-revoke_test.ts`.
  - Cover active, pending, and already-revoked shares; owner mismatch; absent object; provider deletion failure; immediate resolver denial after failure; replay; and redaction.
  - Verification command: `make test-functions`.
- Test author output and coordinator-verified failing command/output (required before READY): Pending.
- Concrete ordered steps:
  1. Verify the existing revoke signature and add failing tests with recorded baseline evidence.
  2. Implement the owner lookup and revoke-first use case.
  3. Add persistence and Storage-delete adapters.
  4. Add the authenticated handler and pinned dependencies.
  5. Verify cleanup handoff and idempotency.
  6. Update evidence, `MEMORY.md`, and `README.md`.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Owner can revoke | Targeted test | Token becomes unusable immediately |
| AC2 | Snapshot deletion is attempted after revoke | Ordered fake assertions | Revoke precedes delete |
| AC3 | Delete failure is durable and retryable | Failure test | `202` and cleanup-pending state |
| AC4 | Repeated revoke is safe | Replay test | Stable result and no reactivation |
| AC5 | Non-owner learns nothing | Authorization test | Uniform 404 |
| AC6 | No provider detail leaks | Error assertion | Bounded public error and stored code |

## Stop conditions

- A revoke signature mismatch, inability to preserve revoke-before-delete ordering, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: Pending.
- Changed files and MEMORY/README update: Pending.
- Test results, including the preimplementation failure and final pass: Pending.
- Outstanding work and review findings with IDs: Pending.
- Technical review status: Pending.
- Human review/commit: Pending; record only actual human authorization.

