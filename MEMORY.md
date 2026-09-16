# Project memory

Last updated: 2026-09-16 — T06 R1 resolved by T012 (REVIEWED and APPROVED); no human commit authorization.
Primary environments: VS Code, Codex, and OpenCode; adapters are in
`opencode.json` and `.vscode/tasks.json`, with guidance in
`docs/development-tools.md`. This file is a current-state aid, not a conversation
history; confirm relevant facts before acting.

## Current state

- Supabase and TypeScript/Deno Edge Functions are selected. The first product migration
  now provides private runtime configuration, owner-scoped settings, and private
  entitlements; Edge Functions and provider endpoints do not yet exist.
- `supabase/migrations/20260915165103_runtime_config_accounts_entitlements.sql`
  creates no seeded business values, keeps configuration/entitlements private, applies
  least-privilege grants/RLS, provisions settings from `auth.users` using only UUIDs,
  and provides fail-closed typed configuration readers and entitlement evaluation.
- `supabase/migrations/20260915181108_garment_registry_and_textual_embeddings.sql`
  adds UUID-only garment lifecycle records and private versioned textual embeddings.
  It deliberately has no image, PII, fixed taxonomy, vector dimension, or ANN index;
  a private advisory-lock trigger enforces the external free-garment limit.
- `supabase/migrations/20260915185258_coordination_primitives.sql` adds private
  fingerprint-only idempotency, cache, lease, rate-window, and bounded-cleanup
  primitives for future Edge Functions. It persists neither raw request/cache keys nor
  provider payloads, PII, locations, images, or device IDs.
- `supabase/migrations/20260915191819_private_share_snapshots.sql` adds a private
  snapshot bucket and opaque token-hash lifecycle; no client Storage policy or raw
  token/object path is persisted.
- `supabase/migrations/20260915193036_preserve_explicit_updated_at.sql` adds a
  dedicated decision-time-aware timestamp trigger for share snapshots without changing
  the strict shared timestamp helper used by client-updatable tables.
- `docs/tasks/006-share-operation-affiliate-persistence.md` through
  `docs/tasks/011-clean-expired-share-snapshots.md` define the pending, dependency-ordered
  Supabase sharing backlog: persistence, signed upload initiation, confirmation,
  public resolution, owner revocation/deletion, and expiry cleanup. They are planning
  records only; no new schema, endpoint, signed URL, or scheduled job is implemented.
  `docs/tasks/012-t06-r1-null-safe-affiliate-fields.md` is the R1 correction
  delivery for T06: REVIEWED and APPROVED.
- T06 share-operation persistence: `supabase/migrations/20260916135232_share_operation_affiliate_persistence.sql`
  adds three private persistence tables (`share_operations`,
  `share_snapshot_affiliate_links`, `share_snapshot_cleanup`) and the atomic service
  function `private.create_share_operation`. The pgTAP suite
  `share_operation_affiliate_persistence.test.sql` covers schema, keys, foreign keys,
  RLS/grants, function hardening, creation/replay/conflict semantics, affiliate
  ordering, structural validation, cleanup initialization, cascade deletion, cross-owner
  isolation, and prohibited-persistence assertions. The historical correction rounds
  (3/3) resolved PL/pgSQL output-variable ambiguity, table-owner ACL stripping, a
  PUBLIC pseudo-role privilege test correction, and added NULL rejection for required
  parameters plus jsonb_typeof string-type checks. Reviewer finding R1 (a two-key
  affiliate object omitting `garment_ref` or `url` evaded the non-null-safe JSON type
  check and failed later with `23502` instead of `P0001`) is RESOLVED by T012, a
  separate task with its own 0/3 round budget, not a fourth correction round: the
  migration's two JSON string-type predicates now use null-safe `is distinct from
  'string'`. A fresh reset applies all six migrations; `make check-all
  CONFIRM_RESET=cloze-backend` passed (no schema lint errors; 5 pgTAP files / 332
  tests; 8 function tests; 40 harness tests; types check skipped because
  `database.types.ts` is absent); `git diff --check` passed. T06 is no longer blocked
  by R1; T012 independently approved the resolution. Human commit authorization is
  pending.
- `supabase/functions/_shared/` provides the reviewed Deno Edge runtime foundation:
  domain repository/result contracts, application invocation, adapter composition, and
  pinned Drizzle/postgres construction. Database URLs fail closed before client creation;
  transaction pooling uses `prepare: false` and callers close the returned handle.
- `supabase/tests/database/runtime_config_accounts_entitlements.test.sql` has 80 pgTAP
  checks covering grants, RLS, ownership, PII minimization, configuration validation,
  entitlement boundaries, and managed timestamp updates. Provider setup is documented in
  `docs/auth-provider-setup.md`; it is manual operational configuration, not SQL.
- Backend quality tooling uses Deno 2.8.2, Supabase CLI 2.105.0, and GNU Make; details
  and evidence are in `docs/tasks/backend-quality-tooling.md`. Apps and landing page
  use other repositories.
- Supabase local ran in an earlier session. Confirm it again for dependent work,
  without printing credentials. Git hooks were installed in this clone through
  `core.hooksPath=.githooks`; each new clone must run the installer.
- The current worktree contains the uncommitted first product-schema delivery alongside
  prior harness work. No publication, deployment, or remote configuration occurred;
  inspect Git before relying on the state.
- Local mitigation received a final Bugbot pass with no actionable bugs and a final
  Security Review pass with no findings. Remote workflow integrity and ruleset
  activation remain explicit owner/admin decisions; do not claim remote enforcement.
- All agents read memory/README on entry and update both after each implementation.
  Pipeline profiles are in `.cursor/agents/`; one writer and an independent reviewer
  work with a maximum of three correction rounds.
- Project skills are installed in `.agents/skills/`, with sources/integrity pinned in
  `skills-lock.json`: `domain-modeling`, `code-review-and-quality`, `supabase`,
  `supabase-postgres-best-practices`, `code-review`, and
  `improve-codebase-architecture`.
- `harness-english-only` is technically REVIEWED and APPROVED; human review remains
  pending. Scoped harness prose is English. Persisted artifacts must be English;
  Spanish and Portuguese user conversations remain permitted.
- `harness-srp-determinism` is technically REVIEWED and APPROVED; human review remains
  pending. It adds practical cohesive-responsibility and deterministic-behavior
  requirements to global guidance, applicable rules, every role prompt, and the workflow.
- The earlier `harness-tdd` delivery is technically reviewed; this mitigation replaces
  its test-author assignment while retaining TDD for Edge Functions, migrations, RLS,
  and database functions.
- The current TDD sequence is DESIGN_READY → restricted test author → coordinator-
  verified baseline failure → READY; see `docs/development-workflow.md`.
- OpenCode registers architect, test-author, developer, and reviewer roles with
  approval-default permissions, secret-read restrictions, denied external-directory,
  delegation, and Vercel access, and role-specific edit/shell permissions.
- Gitleaks is installed by `scripts/install_gitleaks.py` under ignored `.tools/` from
  pinned release and executable checksums. The gate verifies version, uses a minimal
  subprocess environment, scans pushed ref names, and supports introduced-commit ranges.
- GitHub Actions workflow exists for pull requests and pushes to `main`, but is not
  published or run remotely. The `main` ruleset remains inactive pending owner/admin
  configuration after the workflow check appears on GitHub.
- The workflow pins `actions/checkout` v6.1.0 by full SHA for the Node 24 runtime;
  see `.github/workflows/security-gate.yml`.
- Important residual security limits: approval of a test runner or Python command still
  executes checkout-controlled code with the host's authority; review the diff and use
  an isolated credential-free environment. The PR workflow/scanner are also
  self-modifiable, so requiring only the `security-gate` job with zero approvals is not
  tamper-resistant. Owner decision is needed on trusted CI or required independent
  review for gate/control-file changes before claiming remote enforcement.

## Decisions and boundaries

- Product decisions confirmed on 2026-09-15: use OpenWeather Current Weather through
  a server-only Edge integration; classify garments on device and send only normalized
  textual attributes for embeddings; own a versioned V1 taxonomy; rotate a share token
  on renewal; use RevenueCat as the mobile subscription authority. Do not send garment
  images to an AI provider unless a later explicit consent/privacy decision changes
  the local-first boundary.
- Edge architecture decision: use simplified DDD with handlers → application use
  cases → domain ports; adapters implement provider ports and Drizzle-backed repository
  ports. No handler or use case may access Supabase/SQL directly. Before production
  adoption, verify Drizzle's driver compatibility with the Deno Supabase Edge Runtime;
  Drizzle's Supabase documentation requires `prepare: false` for transaction pooling.
- Architect/design produces `DESIGN_READY` task records. Product-code tests are then
  authored and baseline-verified before the coordinator marks them READY. Developers
  execute one at a time and return `NEEDS_CLARIFICATION` for missing decisions.
  OpenCode Zen Big Pickle is the OpenCode first choice and GPT-5.6 Luna (medium) is
  the Codex first choice; the coordinator verifies and records an available free model
  when the selected model is unavailable. No automatic fallback or costly-model inheritance.
- Never create/amend commits without human review and explicit authorization of final
  content. Technical reviewer approval does not authorize a commit.
- All persisted project artifacts—code/comments, tests, documentation, prompts, task
  records, configuration prose, reports, and commit messages—must be English. This
  does not limit Spanish or Portuguese user conversations.
- Local-first: images/closets stay on device; backend stores UUID-linked embeddings
  and minimum metadata. Do not add PII, images, or GPS history without explicit decision.
- Exposed tables require RLS/least privilege; new-table auto-exposure is disabled.
  Future Edge Functions have per-function `deno.json` and pinned dependencies.
- Operational/business configuration is externalized and validated without silent
  fallbacks. Secrets stay out of repository, logs, chat, and documentation.
- Functions and methods have one cohesive responsibility without arbitrary line-count
  targets. Equal explicit inputs and dependencies are deterministic when feasible;
  time, randomness, external state, concurrency, and I/O variation must be explicit,
  bounded and validated where applicable, and tested or documented. Hidden mutable
  state and incidental nondeterminism are prohibited as contract substitutes.

## Directed reading map

| Need | Read |
| --- | --- |
| Agent entry/workflow | `AGENTS.md`, `README.md` |
| Secrets/configuration | `.cursor/rules/secrets-and-configuration.mdc` |
| Harness design | `docs/agentic-harness.md` |
| Pipeline/profiles | `docs/development-workflow.md`, `.cursor/agents/` |
| Tasks/model selection | `docs/atomic-tasks.md`, `docs/templates/atomic-task.md`, `docs/tasks/` |
| Editor integration | `docs/development-tools.md`, `opencode.json`, `.vscode/tasks.json` |
| Controls | `docs/security-hooks.md`, `scripts/security_gate.py`, `.githooks/` |
| Scanner trust | `scripts/install_gitleaks.py`, `scripts/tool-versions.json` |
| Harness tests | `tests/test_security_hooks.py` |
| Local runtime | `supabase/config.toml` |
| Product code | `supabase/functions/`, `supabase/migrations/`, `supabase/tests/` |

External requirements are in parent-workspace `../docs/` and may be absent in an
isolated clone. Obtain them when needed; do not invent them.

## Verification evidence

- Runtime-config delivery: its pgTAP test was written before implementation and `make
  test-db` failed on missing product objects, then passed all 80 tests after the
  migration and timestamp correction. `supabase db lint --local --level warning --fail-on warning` and
  `supabase db advisors --local` found no issues; `make check` passed (security gate,
  formatting/lint/typecheck, and 40 harness tests). The local database was reset only
  after confirming it held no product rows. Independent review approved the artifact
  after resolving the `updated_at` trigger finding.
- Garment-registry delivery: its pgTAP test was written before implementation and
  failed on missing T02 objects. The current fresh local reset passes all 268 combined
  pgTAP tests; lint/advisors, `make check`, and `git diff --check` passed. Independent
  closure review approved the ownership precheck and required index.
- Share-snapshot delivery: a fresh local reset applied all five migrations and passed
  all 268 pgTAP tests. Local lint/advisors, `make check`, and diff check passed. Final
  review approved the forward-only share-specific timestamp trigger correction.
- Edge runtime foundation: `make test-functions` passes 8 tests, Deno type checking
  passes, and `make check` passes its 40-test harness. The final independent review
  approved the pinned/locked driver boundary, fail-closed configuration, and scoped
  static import checks.
- Coordination delivery: its pgTAP test was written before implementation and failed
  on missing T03 objects; after correction and a local reset all three suites passed
  214 checks. Lint/advisors, `make check`, and diff check passed; independent review
  approved the advisory-lock policy-drift fix and readable function bodies.
- T06 share-operation persistence: its pgTAP test was written before implementation
  and failed on missing T06 objects. After two developer correction rounds (PL/pgSQL
  output-variable ambiguity and table-owner ACL stripping) and a test-author
  correction (PUBLIC pseudo-role privilege assertion), a fresh local reset passed 5
  database suites / 319 tests, then the R1 correction round (NULL rejection for all
  required parameters and jsonb_typeof string-type checks for affiliate
  garment_ref/url) passed 5 suites / 329 tests on a fresh reset applying the
  corrected migration. T012 final verification: the coordinator baseline after the
  unchanged migration and a direct local reset failed T06 pgTAP tests 46 and 47
  (caught `23502`, expected `P0001`); after the two null-safe predicate edits,
  `make check-all CONFIRM_RESET=cloze-backend` passed (six migrations applied; no
  schema lint errors; 5 pgTAP files / 332 tests; 8 function tests; 40 harness
  tests; types check explicitly skipped because `database.types.ts` is absent);
  `git diff --check` passed. The developer re-ran the permitted components on the
  reset database: `make db-lint` (no schema errors), `make test-db` (Files=5,
  Tests=332, Result: PASS), `make test-functions` (8 passed), `make types-check`
  (skipped), `git diff --check` (clean). T06 re-review and human commit
  authorization pending.
- Backend quality tooling: `make check` passed (40 tests), `make doctor`, Deno
  format/lint/typecheck, empty pgTAP/function/type checks, local `db-lint`, workflow/JSON
  parsing, and `git diff --check` passed. `make check-all` was not run because the local
  Supabase stack was active and reset would replace uninspected local data. Independent
  review found/fixed `test.ts` discovery; final independent re-review approved. Human review remains pending.
- OpenCode developer-model configuration: `opencode/big-pickle` is active and zero-cost
  with tool-call support; `opencode debug config`, `git diff --check`, and `make check`
  (40 harness tests) passed. Independent re-review approved the corrected model/T06
  README state. Restart OpenCode before delegating so it loads the configuration.
- Earlier harness mitigation: 22 harness tests, the worktree security gate, fresh
  Gitleaks installation, and empty-range scan passed. OpenCode resolved four roles;
  workflow YAML parsed. GitHub workflow/ruleset remain unverified until publication
  and owner/admin setup.

- Earlier hook implementation passed six targeted tests and the worktree security scan.
- Prior English-only, SRP/determinism, TDD, role/pipeline, and skills changes have
  separate task records; technical reviews approved them except skills reviewer R1,
  whose re-review remains pending. No commits were created; human authorization remains
  required for all uncommitted work.

## Outstanding work and next step

- Run the workflow on GitHub after human review/publication, then have an owner/admin
  activate and verify the `main` ruleset requiring PRs and the strict `security-gate` check.
- Implement the OpenWeather Current Weather adapter and its first Edge endpoint using
  the reviewed ports/adapters foundation. Model/taxonomy evolution remains externalized.
- Confirm remote project and Postgres version before linking/deploying.
- T012 independently approved the T06 R1 resolution. After human review, complete the
  pending sharing tasks T07–T11 in dependency order while preserving
  the temporary composite snapshot as the only remote-image exception.
- Local `supabase start` output during `make check-all` printed local DB/API/Storage
  credential values; no publication is authorized and local credential
  rotation/recreation is required before publication.
