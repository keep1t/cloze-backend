# 004 — Private share snapshots and opaque token lifecycle

- Status: IMPLEMENTED
- Source: Cloze V1 sharing architecture and PRD.
- Dependencies: reviewed T01–T03; local private Storage is available.
- Developer: assigned after test-first baseline.

## Contract

Create a private `share-snapshots` Storage bucket and private, RLS-forced
`share_snapshots` persistence. It stores only `share_id`, owner UUID, non-empty unique
opaque `token_hash`, `pending|active|revoked`, upload/share deadlines, activation or
revocation timestamps, and managed timestamps. Index owner and expiry. No image binary,
object path, raw token, embedding, SQLite data, PII, or location lives in Postgres.

The only canonical object name is `shares/<share_id>/snapshot` in `share-snapshots`;
it is derived, never client input. Service-role-only SECURITY INVOKER empty-path
functions create pending records, activate only when the canonical private object exists
before deadlines, resolve only active non-expired token hashes, and revoke only owner
pending/active records. Every business decision receives `p_now`; logical expiry never
resolves. No client Storage policies are created.

## Test-first contract

The restricted author may edit only `supabase/tests/database/share_snapshot_lifecycle.test.sql`.
Test private bucket/policies, exact schema/indexes/RLS/grants/privacy absences, function
signatures/hardening, valid and invalid lifecycle transitions, activation object/deadline
checks, token resolution visibility, revocation ownership, and anon/authenticated denial.
Run `make test-db` before migration and record its expected missing-object failure.

## Boundaries

No signed URL/Edge endpoint, token generation/HMAC algorithm, upload MIME/size checks,
physical deletion/retry, scheduling, or renewal semantics. Renewal is blocked pending a
product choice: retain the token or issue a new token.

## Delivery

- Baseline/evidence: `make test-db` initially failed on missing bucket/table; after implementation and local reset, all four suites passed 262 checks. Local lint/advisors, `make check`, and diff check passed.
- Technical review: pending.
- Human review/commit: pending.
