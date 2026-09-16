# Cloze Backend — agent guide

## Mandatory session entry and handoff — every developer agent

1. At the start of each interaction, read this file, `MEMORY.md`, and `README.md`. On a continuous task, reuse already-read context unless it changed.
2. Inspect `git status --short` and the relevant diff. Use the memory's file map to read only the implementation, requirements and tests needed for the task; do not routinely rescan the whole codebase.
3. Treat memory as a navigation aid and last verified snapshot, not proof of current runtime state. Confirm relevant claims against code/config/tests before relying on them. Resolve contradictions using evidence and correct the documentation.
4. After EVERY implementation (including fixes, configuration, hooks, migrations and tooling), update BOTH `MEMORY.md` and `README.md` in the same change before the final handoff. The implementation is not complete until both are current.
5. In `MEMORY.md`, replace stale state with the implemented result, important decisions, affected paths, checks actually run and their outcomes, unresolved work, and the next concrete step. Record partial work and blockers honestly when interrupted; never mark unverified work as complete.
6. In `README.md`, update the affected setup, usage, capabilities or verification instructions. If those remain unchanged, update its short current-state section with the concrete implementation and a link to details. Do not fabricate changes or merely bump a date.
7. Keep memory concise (target under 150 lines), using repo-relative paths and links to detailed docs. Consolidate old entries; Git history is the change log. Never copy full source, tool output, transcripts, secrets, personal data or environment dumps into memory.
8. Read-only questions/reviews do not require artificial documentation edits. For parallel work, the coordinating developer agent integrates the final memory and README updates; workers report their changes and evidence to it.

This workflow is mandatory for every developer agent, regardless of editor. It is
a completion requirement, not a claim that Git hooks can verify semantic accuracy.

## Human review required before committing — all agents

- Do not create or amend a project commit until a human has reviewed the concrete changes and explicitly authorized committing that reviewed scope.
- Implementation requests, an approved plan, passing checks, agent reviewer `APPROVED`, silence, and prior approval for a different change do not authorize a commit.
- Prepare the complete reviewable result first: code, tests, MEMORY.md and README.md. Present the affected files, relevant diff/new files, verification and limitations, then leave the work uncommitted for human review.
- Authorization applies only to the reviewed content. Further changes outside that content require renewed human review before committing; do not reuse old approval or record approval on the human's behalf.
- This includes `git commit --amend` and equivalent commands/tools that create project commits (merge, cherry-pick, rebase, commit-tree or APIs). Never use another path to evade review. Synthetic temporary test repositories are not project commits and must remain isolated and unpublished.
- Human commit approval does not authorize push or deployment and does not waive secret scans or other checks. Existing Git hooks do not authenticate human approval; this is a mandatory agent workflow rule.

## Product scope

- This repository owns Supabase schema, RLS policies, Edge Functions and their tests.
- Cloze is local-first: garment images and the user's closet live on the device. The backend stores only UUID-linked embeddings and the minimum metadata required for its server-side responsibilities.
- Do not add garment images, device-local database copies, GPS history, or directly identifying user data to Supabase without an explicit product decision.

## Non-negotiable security rules

- All schema changes are SQL migrations created with `supabase migration new <name>`; do not hand-name migration files.
- New tables in exposed schemas must enable RLS and include least-privilege policies in the same migration.
- Policies must express ownership/authorization, not only `TO authenticated`. Use `(select auth.uid()) = user_id` where ownership applies.
- Never authorize from `user_metadata`; never expose `service_role`, secret keys, or provider keys to a client.
- Prefer `SECURITY INVOKER`; any justified `SECURITY DEFINER` function goes in a non-exposed schema, pins `search_path`, checks authorization, and revokes default public execution.

## Mandatory secrets and configuration policy — entire repository

- Follow `.cursor/rules/secrets-and-configuration.mdc` for every change, including documentation, SQL, tests, scripts, and CI. These rules apply regardless of the editor or agent in use.
- Never commit, publish, print, or transmit real secrets in source, logs, tool output, chat, PRs, fixtures, artifacts, or examples. Environment dumps and unfiltered Supabase status output are prohibited; select only required non-sensitive fields.
- No hardcoded credentials, environment-specific URLs/ports/IDs/paths, model names, business limits, prices, timeouts, retries, or feature flags in executable code or SQL. Use validated configuration or managed settings; do not hide literals in constants or fallback expressions.
- Require missing/invalid configuration to fail closed before external calls. Errors name the missing setting, never its value. Document required settings with empty values in example files.
- Before any commit, push, PR publication, or deployment: review the exact outgoing content and run a secret scanner with redacted output. For Git publication, cover the commits being published as well as current files. Missing tooling or unreviewed findings block publication; never bypass checks.
- If a secret is found, stop publication, report only its location/type, remove it from outgoing content, and require revocation/rotation if exposure occurred. Deleting the current literal does not remove Git history.

## Mandatory language policy — persisted artifacts

- All persisted project artifacts must be written in English: code and comments,
  tests, documentation, agent prompts, task records, configuration prose, reports,
  and commit messages.
- This policy does not restrict user conversations: users may communicate in Spanish
  or Portuguese. Translate their requirements accurately into English artifacts.
- Do not change identifiers, protocol literals, product terminology, or third-party
  content solely to satisfy this language policy.

## Edge Function implementation

- Use TypeScript running in the Deno-compatible Supabase Edge Runtime.
- Name functions with kebab-case and keep shared code in `supabase/functions/_shared/`.
- Each function owns a `deno.json`; pin every dependency and favor `npm:` or `jsr:` imports over remote URL imports.
- Validate input, return explicit HTTP status codes, log structured non-sensitive context, and keep handlers short and idempotent.
- Secrets come from `Deno.env.get`; validate their presence at startup and never log them.
- External integrations use ports and adapters: handlers call an application use case,
  use cases depend on domain ports, and provider adapters own HTTP/provider details.
  Do not call an external provider from an HTTP handler or repository.
- Edge Function application code must depend on repository interfaces, never directly
  on Supabase clients, SQL, or table definitions. Drizzle ORM is the persistence
  implementation boundary; select a verified Deno-compatible driver and preserve
  Supabase migrations as the only schema-change mechanism.

## Function responsibility and deterministic behavior

- Give every function or method one cohesive responsibility. Extract code only when a
  responsibility becomes independently meaningful or testable; do not use arbitrary
  line-count targets as a proxy for design quality.
- Default to deterministic output for equal explicit inputs and dependencies whenever
  feasible.
- Make necessary variation from time, randomness, external state, concurrency, or
  I/O explicit at an appropriate boundary. Bound and validate it where applicable,
  and cover it with tests or document its observable behavior.
- Do not use hidden mutable state or incidental nondeterminism as a substitute for a
  defined contract.

## Agent workflow

- Architect/design work must produce DESIGN_READY atomic task files using `docs/atomic-tasks.md` and its template. For product code, the restricted test author writes only specified tests; the coordinator verifies their expected baseline failure before marking the task READY. Developers receive one READY task at a time with verified contracts, bounded files, acceptance evidence and stop conditions. The coordinator validates readiness even for small tasks.
- For product code (Edge Functions, migrations, RLS, database functions), the architect specifies tests, a restricted test author writes them, and the coordinator verifies their expected baseline failure before marking the task READY. The developer implements to pass those tests. TDD does not apply to harness, documentation, or configuration changes.
- Use an explicitly selected, available lower-cost model for developer delegation; do not silently inherit a costly model or invent model IDs. Record the choice in the task; if selection is missing, resolve it before dispatch. Developers return NEEDS_CLARIFICATION instead of guessing missing design decisions.

- Primary development environments are VS Code, Codex and OpenCode. See `docs/development-tools.md`. Use this file as the common entry point; do not assume Cursor rule/agent discovery outside Cursor. OpenCode role adapters live in `opencode.json`; canonical prompts remain shared in `.cursor/agents/`.

- For implementation requests, coordinate the roles in `docs/development-workflow.md` using `.cursor/agents/cloze-{architect,test-author,developer,reviewer}.md`.
- Delegate architecture when warranted and independent review after implementation. The main agent coordinates; only one writer is active at a time. Read-only roles must not edit files; the test-author role may edit only its assigned test paths.
- For small changes, the coordinator may implement directly and delegate review. Never claim independent approval without a separate reviewer. Apply the three-correction-round limit and handoff requirements in the workflow.

1. Read the relevant product requirement before changing behavior. The coordinator
   supplies excerpts and source paths from requirements outside this repository to
   subagents; subagents do not access external directories.
2. Check current Supabase documentation and CLI help before relying on a command or feature.
3. Make the smallest coherent change with cohesive responsibilities and explicit,
   testable variation, then run the checks relevant to the files touched.
4. For database, auth, storage, or function changes, report the RLS/secrets implications and verification performed.

## Baseline checks

- Run `make doctor` to verify the configured versions of Python, Deno, and Supabase
  CLI and to confirm Git, Make, and Docker are available.
- Run `make setup` once per clone to install the checksum-verified scanner and Git
  hooks. The installer preserves a different existing `core.hooksPath` and stops
  for manual integration.
- Run `make check` for security, Deno format/lint/type checks, and harness tests.
- Run `make check-all CONFIRM_RESET=<local-project-id>` for the complete local
  Supabase path. It starts the stack and rebuilds the local database from migrations
  and seed data, replacing local database contents.
- Before publication, run `python3 scripts/security_gate.py worktree`; Git hooks additionally scan the index and pushed history. Never bypass them. See `docs/security-hooks.md` for coverage and limitations.
- When changing the gates, run `python3 -m unittest discover -s tests`.

- Use `make help` for supported local and remote commands. Remote linking, Edge
  Function deployment, and database pushes require an exact `PROJECT_REF` /
  `CONFIRM_REMOTE` match; database pushes run a dry run first.
- The root `deno.json` owns lint and format rules. Each Edge Function keeps its own
  `deno.json` for dependencies and runtime configuration.
