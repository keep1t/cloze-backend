# BACKEND-QUALITY-TOOLING — Reproducible backend checks and command interface

- Status: IMPLEMENTED
- Source request/plan: User-approved plan to configure Deno quality checks and add a Makefile for this Supabase backend.
- Dependencies and evidence they are ready: Existing Supabase/Deno repository, Git hooks, GitHub Actions workflow, and editor task configuration were inspected. The repository has no product migrations, Edge Functions, or tests yet.
- Developer: Coordinator, Codex desktop; direct implementation of a bounded harness/tooling task. Product-code TDD delegation does not apply.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior (before → after): The repository has only manual baseline commands and security checks; it gains pinned Deno formatting/linting, a documented Make command interface, safe local/remote Supabase operations, staged-source hook checks, and CI coverage.
- Out of scope: Application and landing-page linting, product migrations/endpoints, SQLFluff, remote deployments or linking during CI, and project commits.
- Permitted files: `AGENTS.md`, `README.md`, `MEMORY.md`, `.editorconfig`, `Makefile`, `deno.json`, `.githooks/pre-commit`, `.github/workflows/security-gate.yml`, `.vscode/`, `docs/development-tools.md`, `docs/tasks/backend-quality-tooling.md`, `opencode.json`, `scripts/project_tools.py`, `scripts/tool-versions.json`, `supabase/seed.sql`, and relevant tests.
- Proposed new files: `.editorconfig`, `Makefile`, `deno.json`, `scripts/project_tools.py`, `supabase/seed.sql`, `tests/test_project_tools.py`, and this task record.

## Verified minimum context

- Read AGENTS.md, MEMORY.md, and README.md.
- Relevant paths/symbols and what each provides: `supabase/config.toml` identifies the local project and enabled seed file; `.githooks/pre-commit` invokes the secret gate; `.github/workflows/security-gate.yml` runs current checks; `.vscode/settings.json` scopes Deno support; `scripts/tool-versions.json` pins the existing Gitleaks tool.
- Verified contracts/documentation/API and version: Deno 2.8.2 is installed; Supabase CLI 2.105.0 and GNU Make 4.3 are installed. Current Supabase CLI help confirms `db lint --local`, `db reset --local`, `db push --dry-run --linked`, `migration new`, function serving/deployment, and local type generation. Deno lint/format support configuration and stdin input. Supabase's current documentation recommends a separate `deno.json` per Edge Function and documents local Supabase in CI.
- Relevant external product requirements: Not applicable; no product behavior, schema, or authorization changes are included.
- Verified assumptions; open decisions (none for READY): This repository owns only Supabase, PostgreSQL, and Deno Edge Functions. Apps and landing page live in other repositories. Remote operations require exact project-reference confirmation; database reset always targets the local project only.

## Implementation contract

- Inputs, types, validation, and synthetic examples: `FUNCTION` is kebab-case; `NAME` is snake_case; `PROJECT_REF` must match the local-link file and `CONFIRM_REMOTE`; `CONFIRM_RESET` must equal the configured local `project_id`.
- Outputs/errors and edge-case behavior: Missing source/test files produce explicit skips; generated types are written atomically and comparison skips until the artifact exists; local status suppresses URLs and credentials; failed remote dry-run prevents applying migrations.
- Authorization/RLS/privacy and required configuration: No database authorization or schema behavior changes. CI uses no remote credentials. Remote link/deploy/push require explicit confirmation and are denied to OpenCode's delegated developer role. Status output is captured and summarized without URLs or keys.
- Test specifications (for product code): Not applicable; this task changes repository tooling, not product code. Harness tests cover validation, confirmation barriers, remote push ordering, deployment target/order, safe status output, type generation skip, and real Git hook behavior against staged TypeScript.
- Test author output and coordinator-verified failing command/output (required before READY): Not applicable; repository harness/configuration change, not product-code TDD.
- Concrete ordered steps: Configure Deno and editor conventions; add shared Make targets and guarded helper commands; integrate staged checks and pinned two-job CI; update agent guidance/docs/memory; run checks; obtain independent read-only technical review.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Formatting/lint/type checks work with no product source files. | `make fmt-check`, `make lint`, `make typecheck`; Deno 2.8.2. | Commands pass and typecheck reports an explicit skip. |
| AC2 | The Make interface exposes the planned development command groups and validates local tools. | `make help`; `make doctor`. | Help documents reset/remote confirmation and doctor accepts pinned tools. |
| AC3 | Hooks validate exact staged content and preserve security scanning. | `python3 -m unittest discover -s tests`. | Clean staged TypeScript commits; malformed or lint-invalid staged content is blocked even when the worktree differs. |
| AC4 | Remote and destructive commands fail closed. | `python3 -m unittest tests.test_project_tools`. | Invalid/mismatched inputs block CLI calls; dry-run failure blocks migration application; status output contains no URL/key. |
| AC5 | Fast CI avoids Supabase while integration CI only uses an ephemeral local stack. | Inspect workflow and run checks. | Pinned Deno/CLI actions; no remote secrets; integration cleanup always runs. |
| AC6 | Documentation records exact current behavior and real verification. | `git diff --check`; security gate; review. | README, MEMORY and development tool guidance agree; no commit is created. |

## Stop conditions

- If a command can affect a remote project without the exact confirmation and linked-reference checks, block implementation until corrected.
- If staged hook checks read worktree bytes instead of the Git index, reject the result.
- If status or diagnostics expose Supabase keys/URLs, suppress the output before continuing.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run: `make help`, `make doctor`, `make fmt-check`, `make lint`, `make typecheck`, `make test-db`, `make test-functions`, `make types-check`, `make db-lint`, `make check`, and `git diff --check` passed. The harness reports 40 passing tests, including hook-index scenarios and remote/reset guard ordering. `make check-all` was intentionally not run: the local Supabase stack was active and its database contents were not inspected; reset would replace local data. Workflow YAML and JSON configs parsed. No remote operations were run.
- Changed files and MEMORY/README update: Implementation, README, MEMORY, and this task record are updated. Root Deno configuration is scoped to backend functions/tests; Make wraps quality, harness, database, type, and guarded remote operations; hooks validate Git-index bytes; CI separates fast checks from ephemeral Supabase integration.
- Test results: Added regression coverage for plain `test.ts` discovery after review found that valid filename case was omitted. Targeted regression tests passed; full `make check` passed with 40 harness tests.
- Outstanding work and review findings with IDs: Initial independent review found and the implementation fixed `test.ts` test discovery (P2). Final independent re-review approved with no remaining actionable findings. Human review remains pending.
- Technical review status: APPROVED after correction and follow-up review.
- Human review/commit: Pending. No commit, remote link, deployment, or remote database operation occurred.
