# 003 — Private coordination primitives

- Status: REVIEWED
- Source request/plan: Cloze V1 architecture: idempotency registry, private API cache, refresh coalescing, and rate limits.
- Dependencies and evidence they are ready: reviewed T01/T02 migrations provide Auth users, private schema conventions, and managed configuration; `d9444f5` is the clean baseline.
- Developer: the coordinator completed the unchanged READY scope after the baseline; independent review remains required.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior: future verified Edge Functions can atomically coordinate repeat requests without exposing data to clients.
- Out of scope: Edge endpoints, HMAC/canonicalization, secrets, actual TTLs/rate values, scheduler, provider requests, images, PII, device IDs, GPS, and public tables.
- Permitted files: migration created via `make migration NAME=coordination_primitives`, `supabase/tests/database/coordination_primitives.test.sql`, `README.md`, `MEMORY.md`, this record.

## Implementation contract

- Create private RLS-forced tables: `idempotency_operations`, `api_cache_entries`, `api_cache_leases`, and `rate_limit_windows`. Revoke client access; service role receives only CRUD.
- Idempotency is unique on `(user_id, action, idempotency_key_fingerprint)` and stores opaque bytea fingerprints, attempt UUID, `pending|completed` state, validated completed object response/status, explicit expiry and timestamps. Index expiry.
- Cache keys are opaque bytea fingerprints; entries store object response plus explicit fresh/stale deadlines. Leases use fingerprint, holder UUID, and lease deadline. Index cleanup deadlines; never persist raw keys, canonical request, headers, location, or provider payload.
- Rate windows are `(user_id, action, window_started_at)` buckets with positive limit/window, bounded count, explicit end, timestamps, and cleanup index. Never embed endpoint business limits.
- Private SECURITY INVOKER, empty-search-path, non-client-callable functions: `claim_idempotency_operation`, `complete_idempotency_operation`, `read_api_cache`, `write_api_cache`, `acquire_api_cache_lease`, `release_api_cache_lease`, `consume_rate_limit`, `purge_expired_coordination_state`.
- Every decision-taking function receives `p_now` explicitly. Claims/replays/conflicts, TTL validation, fresh/stale/miss boundaries, lease upsert/ownership, and rate policy mismatch all fail closed. Lease acquisition must be a single `INSERT ... ON CONFLICT ... DO UPDATE ... WHERE`; cleanup is deterministic and bounded per resource.

## Test-first contract

The test author edited only `supabase/tests/database/coordination_primitives.test.sql`. Before implementation, `make test-db` failed on missing T03 tables/functions while T01/T02 stayed green. It covers exact schemas/keys/indexes/RLS/grants/PII absences; signatures/path/privileges; idempotency state/reclaim; cache boundaries; lease exclusion/renewal/takeover/release; fixed-window quota/policy mismatch; bounded cleanup; and client denial.

## Criteria and verification

| ID | Observable criterion | Evidence |
| --- | --- | --- |
| AC1 | Duplicate work safely coalesces. | pgTAP idempotency cases. |
| AC2 | Cache data stays private and has deterministic states. | pgTAP cache cases. |
| AC3 | One valid refresh lease holder exists at a time. | pgTAP lease cases. |
| AC4 | Rate use is atomic and policy drift fails closed. | pgTAP quota cases. |
| AC5 | Cleanup is bounded and data never becomes client-readable. | pgTAP, lint, advisors. |
| AC6 | TDD and repository gates pass. | Red baseline, `make test-db`, `make check`, diff check. |

## Delivery

- Baseline/evidence: `make test-db` initially failed on missing coordination objects. After implementation and correction, a local reset passed all three database suites (214 checks); lint/advisors, `make check`, and diff check passed.
- Technical review status: APPROVED after correction round 1. The reviewer independently reran 214 pgTAP tests, `make check`, and diff check.
- Human review/commit: pending.
