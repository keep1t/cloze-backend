# 008 — Confirm upload integrity and activate a private share

- Status: PENDING
- Source request/plan: Implement the authenticated confirmation step in the Eraser V1 Supabase share flow.
- Dependencies and evidence they are ready: Tasks 006 and 007 must be IMPLEMENTED and reviewed; T04's activation contract must remain valid.
- Developer: Unassigned pending coordinator verification of an available cost-effective model and environment. Do not assume model availability.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, a client upload remains pending. After, the authenticated owner can confirm the operation; the backend verifies the exact private object's metadata against the recorded declaration and current configured constraints, activates it once, and returns the reproducible landing URL.
- Out of scope: Uploading, image decoding/content moderation, snapshot composition, public resolution, landing UI, native share selection, and scheduled cleanup.
- Permitted files:
  - `supabase/functions/share-confirm/**`
  - Necessary share-confirm files under `supabase/functions/_shared/**`
  - `supabase/config.toml` if needed
  - `supabase/tests/functions/share-confirm_test.ts`
  - `docs/tasks/008-confirm-private-share-activation.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files:
  - `supabase/functions/share-confirm/index.ts`
  - `supabase/functions/share-confirm/deno.json`
  - Confirmation use case and required ports/adapters
  - `supabase/tests/functions/share-confirm_test.ts`

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: T04 activation function and path checks, T05 Edge boundaries, task 006 operation lookup, and task 007 token/configuration contracts.
- Verified contracts/documentation/API and version:
  - [Supabase Edge authentication](https://supabase.com/docs/guides/functions/auth)
  - [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
  - Storage object metadata behavior and fields must be verified against current official documentation before READY.
  - Verified dependencies must be pinned in this function's `deno.json`.
- Relevant external product requirements: F3.1–F3.3, NF2, and NF5. Heavy composition remains on-device; the server verifies metadata, not composition.
- Verified assumptions; open decisions:
  - Confirmation accepts `operationId`; it does not accept owner, object path, expiry, or share ID as authority.
  - Exact Storage metadata API behavior and fields must be verified before READY.
  - If metadata cannot establish the declared content type and size, activation fails closed.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - `POST /functions/v1/share-confirm`
  - Required user JWT plus `{ "operationId": "<uuid>" }`.
- Outputs/errors and edge-case behavior:
  - `200`: `{ shareId, operationId, status: "active", expiresAt, landingUrl }`.
  - Repeated confirmation is idempotent and returns the same landing URL.
  - Missing object: `409 UPLOAD_NOT_FOUND`.
  - Wrong path, MIME, size, owner, expired pending share, or already revoked share produces a typed rejection without activation.
  - An invalid uploaded object is deleted best-effort and marked for cleanup if deletion fails.
  - `401`, non-enumerating `404`, `409`, `422`, `503`, and sanitized `500` follow the shared error envelope.
- Authorization/RLS/privacy and required configuration:
  - The JWT subject must own the mapped operation/share.
  - Metadata is read with a server-only client; service credentials never reach clients.
  - Revalidate configured MIME and byte limits at confirmation even if initiation already validated them.
  - Activation must not extend the original configured 15-day expiry.
  - Landing URL is built from validated `SHARE_LANDING_BASE_URL` and the reproducible opaque token.
- Test specifications (for product code):
  - Test author path: `supabase/tests/functions/share-confirm_test.ts`.
  - Cover success, duplicate confirmation, absent upload, wrong owner/path/MIME/size, expiry race, revoked share, configuration failure, deletion failure handoff, and secret/error redaction.
  - Verification command: `make test-functions`.
- Test author output and coordinator-verified failing command/output (required before READY): Pending.
- Concrete ordered steps:
  1. Verify T04 activation and Storage metadata contracts.
  2. Add failing tests and record their baseline.
  3. Implement the confirmation use case and ports.
  4. Implement metadata and persistence adapters.
  5. Add the thin authenticated handler and pinned `deno.json`.
  6. Verify races and idempotency.
  7. Update evidence, `MEMORY.md`, and `README.md`.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Valid uploaded object activates once | Targeted test | Active response and landing URL |
| AC2 | Confirmation is idempotent | Repeat test | Same URL and no duplicate transition |
| AC3 | Invalid metadata never activates | Metadata matrix | Typed rejection and cleanup handoff |
| AC4 | Only the owner can confirm | JWT-owner tests | Non-enumerating denial |
| AC5 | Original expiry is preserved | Injected-clock test | Confirmation never renews TTL |
| AC6 | Configuration and provider errors fail closed | Failure tests | No activation or secret leakage |

## Stop conditions

- Missing Storage metadata guarantees, a contract mismatch, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: Pending.
- Changed files and MEMORY/README update: Pending.
- Test results, including the preimplementation failure and final pass: Pending.
- Outstanding work and review findings with IDs: Pending.
- Technical review status: Pending.
- Human review/commit: Pending; record only actual human authorization.

