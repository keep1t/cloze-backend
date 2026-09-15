# Project memory

Last updated: 2026-09-15 — backend quality tooling reviewed; human review pending.
Primary environments: VS Code, Codex, and OpenCode; adapters are in
`opencode.json` and `.vscode/tasks.json`, with guidance in
`docs/development-tools.md`. This file is a current-state aid, not a conversation
history; confirm relevant facts before acting.

## Current state

- Bootstrap phase: Supabase and TypeScript/Deno Edge Functions are selected. Local
  configuration and directory structure exist; product migrations, functions, and
  endpoint tests do not.
- Backend quality tooling uses Deno 2.8.2, Supabase CLI 2.105.0, and GNU Make; details
  and evidence are in `docs/tasks/backend-quality-tooling.md`. Apps and landing page
  use other repositories.
- Supabase local ran in an earlier session. Confirm it again for dependent work,
  without printing credentials. Git hooks were installed in this clone through
  `core.hooksPath=.githooks`; each new clone must run the installer.
- The current worktree includes uncommitted backend tooling and prior harness changes.
  No publication or deployment occurred; inspect Git before relying on the state.
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

- Architect/design produces `DESIGN_READY` task records. Product-code tests are then
  authored and baseline-verified before the coordinator marks them READY. Developers
  execute one at a time and return `NEEDS_CLARIFICATION` for missing decisions.
  GPT-5.6 Luna (medium)
  is first choice; if GPT quota is exhausted, the coordinator verifies and records a
  free model. No automatic fallback or costly-model inheritance.
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

- Backend quality tooling: `make check` passed (40 tests), `make doctor`, Deno
  format/lint/typecheck, empty pgTAP/function/type checks, local `db-lint`, workflow/JSON
  parsing, and `git diff --check` passed. `make check-all` was not run because the local
  Supabase stack was active and reset would replace uninspected local data. Independent
  review found/fixed `test.ts` discovery; final independent re-review approved. Human review remains pending.
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
- Define the first data contract/model, ownership, and RLS tests.
- Confirm remote project and Postgres version before linking/deploying.
- Resolve classification/outfit-sharing flows while images remain on-device.
