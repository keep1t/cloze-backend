# 009 — Resolve an active public share without exposing private Storage

- Status: PENDING
- Source request/plan: Implement the public Supabase backend contract consumed by the mobile landing page.
- Dependencies and evidence they are ready: Tasks 006 and 007 must be IMPLEMENTED and reviewed. Task 008 may be developed in parallel but must be implemented for end-to-end verification.
- Developer: Unassigned pending coordinator verification of an available cost-effective model and environment. Do not assume model availability.
- Global assignment correction round: 0 of 3.

## Outcome and boundaries

- Expected behavior (before → after): Before, no public endpoint can resolve a share. After, a valid opaque token for an active, unexpired share returns a short-lived signed download URL, sanitized garment affiliate links, and non-sensitive expiry data while the Storage bucket remains private.
- Out of scope: HTML/landing UI, app-download CTA rendering, affiliate redirects/click tracking, activation, renewal, analytics, and source garment images.
- Permitted files:
  - `supabase/functions/share-resolve/**`
  - Necessary resolver files under `supabase/functions/_shared/**`
  - `supabase/config.toml` for the intentional public function setting
  - `supabase/tests/functions/share-resolve_test.ts`
  - `docs/tasks/009-resolve-public-share.md`
  - `MEMORY.md`
  - `README.md`
- Proposed new files:
  - `supabase/functions/share-resolve/index.ts`
  - `supabase/functions/share-resolve/deno.json`
  - Resolution use case and ports/adapters
  - `supabase/tests/functions/share-resolve_test.ts`

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: T04 token-hash resolver, task 006 affiliate rows, and T05 architecture.
- Verified contracts/documentation/API and version:
  - [Create signed download URL](https://supabase.com/docs/reference/javascript/file-buckets-createsignedurl)
  - [Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
  - [Authorization-header behavior](https://supabase.com/docs/guides/functions/auth-headers)
  - Function dependencies must be verified and pinned before implementation.
- Relevant external product requirements: F3.3–F3.4, NF2/NF4, and the conversion strategy requiring a fast mobile landing page with outfit, creator affiliate links, and app-download CTA. This endpoint supplies data; the UI lives elsewhere.
- Verified assumptions; open decisions:
  - The function is intentionally public. The exact current Supabase mechanism for public invocation must be verified before READY and explicitly represented in `supabase/config.toml`.
  - Proposed request uses the token in a JSON body rather than query parameters to reduce accidental URL/log leakage. The landing application may receive the token in its route and POST it to this endpoint.
  - Required `SHARE_DOWNLOAD_URL_TTL_SECONDS` has no code default and must be explicitly selected and configured before READY.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - `POST /functions/v1/share-resolve`
  - `{ "token": "<base64url opaque token>" }`.
  - Enforce exact token alphabet and length before hashing; hash injected/testable UTF-8 bytes with SHA-256.
- Outputs/errors and edge-case behavior:
  - `200`: `{ share: { expiresAt, snapshot: { signedUrl, expiresAt }, affiliateLinks: [{ garmentRef, url, position }] } }`.
  - Missing, malformed, unknown, pending, revoked, expired, or physically deleted shares all return the same non-enumerating `404 SHARE_NOT_FOUND`.
  - Storage signing failure returns sanitized `503 SHARE_TEMPORARILY_UNAVAILABLE` without bucket/path/service details.
  - Never return owner UUID, operation ID, token hash, object path, internal status, or service credentials.
- Authorization/RLS/privacy and required configuration:
  - The public caller has no database or Storage grants.
  - The handler calls a service-only application adapter after strict token validation.
  - T04's resolver remains the authority for active/unexpired state.
  - Signed download lifetime comes from validated configuration and cannot exceed the remaining share lifetime.
  - Affiliate links are only the canonical sanitized values persisted during creation.
  - Add explicit cache headers preventing token-bearing request/response caching unless a reviewed policy states otherwise.
- Test specifications (for product code):
  - Test author path: `supabase/tests/functions/share-resolve_test.ts`.
  - Cover active success, token-hash input, all non-active states sharing one 404 shape, signed URL TTL capped by share expiry, public invocation, private bucket preservation, affiliate order, omitted internals, configuration failure, provider error redaction, and non-cache headers.
  - Verification command: `make test-functions`.
- Test author output and coordinator-verified failing command/output (required before READY): Pending.
- Concrete ordered steps:
  1. Resolve public-function configuration and download TTL, then verify T04's resolver signature.
  2. Add failing tests and record their baseline.
  3. Implement token parser/hash and resolution use case.
  4. Add persistence and signed-download adapters.
  5. Add the thin public handler and pinned dependencies.
  6. Verify non-enumeration, caching behavior, and response privacy.
  7. Update evidence, `MEMORY.md`, and `README.md`.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Active token resolves | Targeted test | Signed image URL and ordered sanitized links |
| AC2 | All unusable tokens are non-enumerating | State matrix | Same 404 status/body |
| AC3 | Bucket remains private | Integration/grant assertions | Object is unavailable without a signed URL |
| AC4 | Download URL is short-lived | Injected clock/config test | TTL is configured and capped by share expiry |
| AC5 | Internal ownership/storage data is absent | Response-schema test | No sensitive fields |
| AC6 | Public mode is explicit | Config inspection/test | No user JWT is required and no service secret is exposed |

## Stop conditions

- Unresolved public-function configuration/download TTL, a resolver mismatch, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: Pending.
- Changed files and MEMORY/README update: Pending.
- Test results, including the preimplementation failure and final pass: Pending.
- Outstanding work and review findings with IDs: Pending.
- Technical review status: Pending.
- Human review/commit: Pending; record only actual human authorization.

