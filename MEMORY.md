# Project memory

Last updated: 2026-09-14 — function responsibility and deterministic-behavior policy implemented.
Primary environments: VS Code, Codex, and OpenCode; adapters are in
`opencode.json` and `.vscode/tasks.json`, with guidance in
`docs/development-tools.md`. This file is a current-state aid, not a conversation
history; confirm relevant facts before acting.

## Current state

- Bootstrap phase: Supabase and TypeScript/Deno Edge Functions are selected. Local
  configuration and directory structure exist; product migrations, functions, and
  endpoint tests do not.
- Supabase local ran in an earlier session. Confirm it again for dependent work,
  without printing credentials. Git hooks were installed in this clone through
  `core.hooksPath=.githooks`; each new clone must run the installer.
- Bootstrap files remain uncommitted at the latest inspection. Consult Git; do not
  assume publication or deployment.
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

## Decisions and boundaries

- Architect/design produces READY atomic task records. Developers execute one at a
  time and return `NEEDS_CLARIFICATION` for missing decisions. GPT-5.6 Luna (medium)
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
| Harness tests | `tests/test_security_hooks.py` |
| Local runtime | `supabase/config.toml` |
| Product code | `supabase/functions/`, `supabase/migrations/`, `supabase/tests/` |

External requirements are in parent-workspace `../docs/` and may be absent in an
isolated clone. Obtain them when needed; do not invent them.

## Verification evidence

- Earlier hook implementation: six tests passed, including staged/historical secret,
  hardcoding, and scanner-failure cases; worktree scan passed.
- Earlier role/pipeline and human-review policy changes received independent technical
  approval; scans passed. No project commits were created; human authorization pending.
- Earlier OpenCode setup resolved three subagents; prompt/reviewer restrictions and
  VS Code task JSON were verified. No OpenCode LLM session or VS Code UI task ran.
- Earlier Luna setup verified `github-copilot/gpt-5.6-luna` and `medium` through
  `opencode models github-copilot`; JSON, diff, and security checks passed.
- Earlier skills installation passed `npx skills list --json`, `opencode debug skill`,
  diff, and security checks. Reviewer R1 remains pending re-review.
- Current change translated scoped project-owned harness prose and added English-only
  policy to AGENTS, role prompts, and workflow. `git diff --check` and
  `python3 scripts/security_gate.py worktree` passed; scoped common-Spanish-prose
  search found no matches. Independent review returned APPROVED. No commit was
  created; human review and explicit commit authorization remain pending.
- `harness-srp-determinism` updated `AGENTS.md`, `.cursor/rules/core.mdc`,
  `.cursor/rules/edge-functions.mdc`, all `.cursor/agents/cloze-*.md` prompts, and
  `docs/development-workflow.md`. `git diff --check` and
  `python3 scripts/security_gate.py worktree` passed. A scoped search confirmed the
  policy in required instructions, rules, prompts, and workflow. No product behavior,
  RLS, privacy, secrets, or runtime configuration changed. Independent review returned
  APPROVED; no commit was created and human authorization remains pending.

## Outstanding work and next step

- Add mandatory CI and branch protection.
- Define the first data contract/model, ownership, and RLS tests.
- Confirm remote project and Postgres version before linking/deploying.
- Resolve classification/outfit-sharing flows while images remain on-device.
