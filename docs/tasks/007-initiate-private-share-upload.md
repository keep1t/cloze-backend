# 007 — Initiate an idempotent private snapshot upload

- Status: PENDING
- Source request/plan: Implement the authenticated Supabase Edge API consumed when the app begins the Eraser V1 share flow.
- Dependencies and evidence they are ready: T03–T05 are REVIEWED; task 006 must be IMPLEMENTED and independently reviewed.
- Developer: Unassigned pending coordinator verification of an available cost-effective model and environment. Do not assume model availability.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, no concrete Edge endpoint can create a pending share or authorize upload. After, an authenticated client can submit one operation and sanitized affiliate-link set, receive a pending share contract and signed upload authorization for the canonical private object path, and safely retry the same operation.
- Out of scope: Snapshot composition, proof of ownership of a local-only outfit beyond the authenticated user initiating the new server share, upload bytes, activation, public resolution, landing UI, native share selection, revocation, and scheduled cleanup.
- Permitted files:
  - `supabase/functions/share-create/**`
  - Necessary share-specific files under `supabase/functions/_shared/application/`, `supabase/functions/_shared/domain/`, and `supabase/functions/_shared/adapters/`
  - `supabase/config.toml` only if function registration is required
  - `supabase/tests/functions/share-create_test.ts`
  - `docs/tasks/007-initiate-private-share-upload.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files:
  - `supabase/functions/share-create/index.ts`
  - `supabase/functions/share-create/deno.json`
  - Share-create use case, ports, adapters, and domain value objects following T05 conventions
  - `supabase/tests/functions/share-create_test.ts`

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: T03 idempotency functions, T04 pending-share creation and private Storage path contract, T05 shared Edge runtime architecture, and task 006 owner/operation mapping and affiliate persistence.
- Verified contracts/documentation/API and version:
  - [Supabase Edge Function authentication](https://supabase.com/docs/guides/functions/auth)
  - [Authorization headers and per-function verification](https://supabase.com/docs/guides/functions/auth-headers)
  - [Create signed upload URL](https://supabase.com/docs/reference/javascript/file-buckets-createsigneduploadurl), whose current documented upload-token lifetime is two hours
  - [Upload to signed URL](https://supabase.com/docs/reference/javascript/file-buckets-uploadtosignedurl)
  - [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
  - Actual Deno/npm package versions must be verified and pinned in the function-local `deno.json` during implementation.
- Relevant external product requirements: F3.1–F3.4, NF2, NF4, and NF5 from the coordinator-supplied source excerpts. Only the already-approved temporary composite snapshot may be uploaded.
- Verified assumptions; open decisions:
  - Because no cloud outfit record exists, the server cannot prove ownership of a local snapshot. It authenticates the JWT, creates a new share owned by the JWT subject, binds the canonical path to that owner/share, and never trusts a client-supplied owner/path.
  - Proposed replayable opaque token: unpadded base64url of HMAC-SHA-256 over a versioned, domain-separated encoding of authenticated owner UUID and operation UUID. Store only SHA-256 of the resulting token. Security review must approve this before READY.
  - Proposed required configuration names: `SHARE_TOKEN_KEYS`, `SHARE_TOKEN_ACTIVE_KEY_VERSION`, `SHARE_SNAPSHOT_TTL_SECONDS`, `SHARE_SNAPSHOT_MAX_BYTES`, `SHARE_SNAPSHOT_ALLOWED_MIME_TYPES`, `SHARE_AFFILIATE_MAX_LINKS`, `SHARE_AFFILIATE_URL_MAX_LENGTH`, `SHARE_AFFILIATE_ALLOWED_HOSTS`, and `SHARE_LANDING_BASE_URL`.
  - Values must be selected and provisioned before READY; there are no code defaults for business values. The deployed `SHARE_SNAPSHOT_TTL_SECONDS` value must represent 15 days.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - `POST /functions/v1/share-create`
  - Required `Authorization: Bearer <user JWT>`.
  - JSON: `{ "operationId": "<uuid>", "snapshot": { "contentType": "image/jpeg", "byteLength": 734003 }, "affiliateLinks": [{ "garmentRef": "look-item-2", "url": "https://shop.example/products/blue-shirt" }] }`.
  - Reject malformed UUIDs, non-integer/nonpositive lengths, disallowed MIME types, sizes above the configured maximum, too many links, duplicate garment/link entries, URLs over the configured length, non-HTTPS URLs, credentials, fragments, non-allowlisted hosts, IP-literal/private-network hosts, and noncanonical URLs.
  - Sanitization returns a canonical HTTPS URL and is a pure tested domain function.
- Outputs/errors and edge-case behavior:
  - `201`: `{ shareId, operationId, status: "pending", expiresAt, upload: { path, signedUrl, token, expiresAt }, constraints: { maxBytes, allowedMimeTypes } }`.
  - Pending replay: `200` with the same `shareId`, path, and token-derived identity, plus a newly issued signed upload authorization if the previous one may have expired.
  - Active replay: `200` with `{ shareId, operationId, status: "active", expiresAt, landingUrl }`.
  - Errors: `400 INVALID_REQUEST`, `401 UNAUTHENTICATED`, `409 IDEMPOTENCY_CONFLICT`, `422 AFFILIATE_URL_REJECTED` or `SNAPSHOT_CONSTRAINT_REJECTED`, `503 CONFIGURATION_INVALID`, and sanitized `500 INTERNAL_ERROR`.
  - Never return another owner's existence or a provider error body.
- Authorization/RLS/privacy and required configuration:
  - Validate the user JWT according to the project's verified Supabase auth mode and use the JWT subject, never `user_metadata`, as owner.
  - A server-only admin/service client may call private persistence and Storage signing; its key never reaches responses or logs.
  - The handler performs HTTP translation only; the application use case owns orchestration; ports abstract auth, time, token derivation, persistence, and Storage; adapters own Supabase calls.
  - Time and cryptographic operations are injected and deterministic in unit tests.
  - Validate all required configuration and fail closed without logging values.
- Test specifications (for product code):
  - Test author path: `supabase/tests/functions/share-create_test.ts`.
  - Cover success, invalid/missing JWT, owner spoof attempt, pending replay, active replay, cross-owner isolation, conflicting payload, sanitization matrix, missing config, deterministic clock/token fixtures, no secret/raw-token persistence, provider error redaction, and the exact canonical path passed to Storage.
  - Verification command: `make test-functions`.
- Test author output and coordinator-verified failing command/output (required before READY): Pending.
- Concrete ordered steps:
  1. Resolve the listed security/configuration decisions and verify shared T05 ports and conventions.
  2. Add failing tests and record their baseline.
  3. Implement pure request, URL, configuration, and token value objects.
  4. Implement the create-share use case against injected ports.
  5. Add persistence/auth/Storage adapters.
  6. Add the thin handler and function-local pinned dependency configuration.
  7. Run targeted tests, then repository verification.
  8. Update task evidence, `MEMORY.md`, and `README.md`.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Authenticated initiation creates one pending share | Targeted Deno test with fakes | `201` and canonical private upload contract |
| AC2 | Retry does not create a second share | Replay tests | Same owner/operation yields the same share |
| AC3 | Active replay returns the existing landing URL | Completed-operation fixture | `200` with identical token-derived URL |
| AC4 | Upload limits and affiliate URLs fail closed | Validation table tests | Invalid input never reaches persistence or Storage |
| AC5 | Owner/path cannot be spoofed | Authorization tests | JWT subject controls owner and server controls path |
| AC6 | No secret or provider detail leaks | Response/log assertions | Sanitized errors and responses |
| AC7 | Local-first boundary is preserved | Port-call assertions and review | Only one temporary composite object is authorized |

## Stop conditions

- Missing information, a shared-runtime mismatch, unapproved token derivation, unselected required configuration, or scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: Pending.
- Changed files and MEMORY/README update: Pending.
- Test results, including the preimplementation failure and final pass: Pending.
- Outstanding work and review findings with IDs: Pending.
- Technical review status: Pending.
- Human review/commit: Pending; record only actual human authorization.

