# 002 — Garment registry and versioned textual embeddings

- Status: IMPLEMENTED
- Source request/plan: Implement the Supabase backend from the Cloze V1 architecture and PRD through the Cloze pipeline.
- Dependencies and evidence they are ready: task 001 is technically REVIEWED; it provides private typed configuration readers, private entitlement evaluation, the pinned-path `updated_at` trigger, Auth users, and owner-settings conventions.
- Developer: the verified lower-cost `gpt-5.6-luna` medium assignment is unavailable because its quota was exhausted in task 001. The coordinator will implement this unchanged READY scope directly and request independent review.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior (before → after): there is no server-side garment identity registry or embedding store → each user can own only opaque garment UUIDs and state; the server can retain versioned vector embeddings plus structured textual attributes without ever retaining a garment image, local closet database, GPS history, display name, caption, or direct PII.
- Out of scope: image upload/storage, visual classification, model invocation, fixed vector dimension, vector ANN indexing, user-facing taxonomy/category vocabulary, recommendation generation, trips, weather, sharing, and subscription reconciliation.
- Permitted files: the migration created for this task, `supabase/tests/database/garment_registry_and_embeddings.test.sql`, `README.md`, `MEMORY.md`, and this record.
- Proposed new files: one timestamped migration and one pgTAP test file.

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Relevant paths/symbols and what each provides: task 001 defines `private.product_config`, `private.get_config_integer`, `private.get_config_text`, `private.has_active_entitlement`, and `private.set_updated_at`; `supabase/config.toml` exposes only `public`/`graphql_public` and disables automatic public-table exposure.
- Verified contracts/documentation/API and version: the local stack uses PostgreSQL 17. Current Supabase guidance requires separate SQL grants and RLS, owner predicates based on `(select auth.uid())`, and empty `search_path` plus revoked `PUBLIC` execute for privileged functions. pgvector supports an unconstrained `vector` column, but model/dimension selection and ANN indexing must wait for explicit product decisions.
- Relevant external product requirements: the Eraser diagram requires local garment images, UUID-linked versioned textual embeddings only, Edge-only secrets, and active supplied UUID validation. The PRD requires a configurable Free active-garment limit, server-side entitlement validation, and external model/taxonomy decisions.
- Verified assumptions; open decisions (none for READY): this task uses generic structured attributes and an unconstrained vector column deliberately. It makes no taxonomy, model, dimension, index, or provider decision.

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - Create `public.garment_registry` with `garment_id uuid` primary key, `user_id uuid` FK to `auth.users`, `status` constrained to `active|archived`, `archived_at`, and managed timestamps. An active garment has null `archived_at`; an archived garment has a non-null archive timestamp.
  - Create `private.garment_text_embeddings` with a FK to the registry, non-empty `embedding_model`, positive `embedding_revision`, positive `attributes_schema_version`, object-only `attributes`, an unconstrained `extensions.vector` embedding, and creation timestamp. Its key is `(garment_id, embedding_model, embedding_revision)`.
  - Do not create image/blob/text-caption fields. `attributes` accepts only a JSON object and must not introduce a fixed category vocabulary.
  - Add a security-definer, empty-path trigger function that fails closed on active registry insert/reactivation unless either the owner holds the externally named premium entitlement or the owner has fewer active garments than `limits.free.active_garments`. The premium entitlement key is read from `entitlements.premium.key`; it must be non-empty. Serialize the per-user count check with a transaction-scoped advisory lock. Configuration errors remain fail-closed.
- Outputs/errors and edge-case behavior:
  - Archive/reactivate operations preserve identity. Reactivation counts toward the configured active limit; archiving does not. A premium active entitlement bypasses only the active-garment count, not ownership/RLS.
  - The untyped vector intentionally permits future model versions with distinct dimensions. No cross-model similarity query or vector index is introduced here.
- Authorization/RLS/privacy and required configuration:
  - Enable and force RLS on both tables. Authenticated users receive only owner-scoped CRUD on `public.garment_registry`, using `(select auth.uid()) = user_id` for both `USING` and `WITH CHECK`; no client may access the private embedding table.
  - Revoke private table/function access from `PUBLIC`, `anon`, and `authenticated`; service role receives only the private embedding CRUD needed by future verified Edge Functions. The limit trigger function is non-executable by clients and pins its search path.
  - Required managed keys, documented but never seeded: `limits.free.active_garments` (positive bounded integer) and `entitlements.premium.key` (non-empty text). Existing T01 keys stay external configuration.
- Test specifications (for product code): `supabase/tests/database/garment_registry_and_embeddings.test.sql` must verify schema/privacy absences, RLS/grants/owner behavior, archive invariants, private embedding denial, no fixed vector typmod/index, vector and JSON validation, configurable free limit/re-activation/premium bypass, fail-closed missing or invalid config, timestamp updates, and private function hardening. Verify with `make test-db`.
- Test author output and coordinator-verified failing command/output (required before READY): the restricted test author created `supabase/tests/database/garment_registry_and_embeddings.test.sql` before production work. On 2026-09-15, `make test-db` failed as expected: the first six T02 assertions reported missing pgvector/schema/function objects, then PostgreSQL stopped because `public.garment_registry` did not exist; the T01 suite remained green. This is the recorded red baseline.
- Concrete ordered steps:
  1. Restricted test author creates only the pgTAP contract.
  2. Coordinator runs `make test-db` before the migration and records its expected failure.
  3. Coordinator updates this record to READY and creates the migration through `make migration`.
  4. One developer implements only the described migration and documentation updates.
  5. Coordinator validates the database suite, lint/advisors, repository checks, updates memory/README, and requests independent review.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Registry ownership and archive lifecycle are isolated. | `make test-db` with local stack | Owners can only manipulate their own UUIDs; state/archive constraints and timestamps hold. |
| AC2 | Embeddings remain private, minimal, and versioned. | `make test-db` | Client roles cannot access them; JSON/vector/version constraints hold; image/PII fields and fixed dimensions are absent. |
| AC3 | Free limits are externalized and enforced safely. | `make test-db` | Configured quota applies to insert/reactivation, premium bypass is valid only while active, and missing/invalid config fails closed. |
| AC4 | Tests are red before implementation and green afterward. | Recorded baseline plus `make test-db` | Expected missing-object failure precedes final passing suite. |
| AC5 | Least privilege and project gates are preserved. | DB lint/advisors, `make check`, and diff check | No advisor/schema issues; quality/security gates pass. |

## Stop conditions

- Missing information, code mismatch, or required scope expansion: return NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: AC1–AC4 passed through `make test-db` (151 combined pgTAP tests); AC5 passed through local database lint, advisors, `make check`, and `git diff --check`. No remote action, deployment, or commit was run.
- Changed files and MEMORY/README update: the task migration and pgTAP contract were added; README and MEMORY.md now describe the UUID-only registry and private embeddings.
- Test results: T02 initially failed on missing objects while T01 remained green. One production correction ensured invalid active/archive combinations defer to their declarative constraint before quota evaluation; final combined tests pass 151 checks.
- Outstanding work and review findings with IDs: independent technical review pending.
- Technical review status: pending.
- Human review/commit: pending; record only actual human authorization.
