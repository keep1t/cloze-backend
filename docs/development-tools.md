# VS Code, Codex, and OpenCode

Open `cloze-backend` as the project root (or a folder in a multi-root workspace).
Tasks use that root; opening only the parent folder requires selecting the backend
folder. The current environment uses Linux tools; tasks require Python 3 and a POSIX
shell wherever they run.

## Shared instructions

`AGENTS.md` is the common entry point. It requires reading memory/README, following
secret rules, and completing the pipeline. Role prompts remain in `.cursor/agents/`
as the single source for compatibility; their location does not imply using Cursor.
Shared skills are versioned in `.agents/skills/` and `skills-lock.json` pins their
source and integrity. The installer configured them for Codex and OpenCode; consult
`npx skills list --json` to verify parity in each environment. Read `.mdc` rules
referenced by AGENTS as documents: do not assume Codex or OpenCode auto-discovers
Cursor rules.

## Make and local tooling

Run `make doctor` to verify Git, GNU Make 4.3+, Docker, Python 3.11+, and the pinned Deno
and Supabase CLI versions from `scripts/tool-versions.json`. Run `make setup` once per
clone to install the verified Gitleaks scanner and repository hooks.

The repository-root `deno.json` owns formatter and linter policy for
`supabase/functions` and `supabase/tests`; it succeeds while those directories contain
no source. Future Edge Functions retain their own `deno.json` files for dependencies.
`make typecheck` uses the nearest function configuration for each entrypoint.
`.editorconfig` supplies shared whitespace and line-ending defaults.

`make check` runs the secret/hardcoding scan first, followed by format, lint, type
checks, and Python harness tests. `make check-all CONFIRM_RESET=<local-project-id>`
starts Supabase and resets only the local database before running database lint,
available pgTAP and Deno tests, and generated-type verification. The reset replaces
local database contents and requires a confirmation matching `project_id` in
`supabase/config.toml`.

Run `make help` for local development and remote operation targets. The VS Code task
menu includes the quick checks, the explicitly confirmed full local check, stack
start/stop, scanner installation, harness tests, and hook installation. TypeScript
format-on-save uses the Deno formatter in the backend workspace.

`make remote-link`, `make deploy-function`, and `make db-push` require an exact
`PROJECT_REF` / `CONFIRM_REMOTE` match; these operations are denied to OpenCode's
delegated developer role. Function deployment targets one existing kebab-case
function and runs `make check`. Database push performs a linked dry run before
applying migrations. CI never links to or mutates a remote project and never prints
Supabase status credentials.

GitHub Actions has two jobs: `security-gate` runs the quick `make check` path and
scans introduced commits; `supabase-integration` installs the pinned CLI, starts an
ephemeral local stack, resets its local database, runs database lint and available
tests, checks generated types, and stops the stack during cleanup. No remote
credentials are supplied to either job.

## VS Code

The editor alone does not run the agent pipeline; use Codex or OpenCode through its
integration or terminal.

## Codex

Codex uses `AGENTS.md` as project instructions. The coordinator reads versioned
prompts and passes them to available subagent tools. It selects GPT-5.6 Luna (medium)
for the developer at subagent creation and records it in the READY task. If GPT quota
is exhausted, it manually selects and records an available free model; Codex receives
no repository automatic fallback. This repository does not configure native Codex role
registration or change global settings. If a session cannot delegate, report that
independent review is missing.

## OpenCode

`opencode.json` registers four roles as subagents, reusing prompt files and adding
memory and README instructions. The test author can edit only `supabase/tests/**`;
architect and reviewer cannot edit or run shell commands. All subagents are blocked
from external directories and delegation. Web access requires approval. Developer
shell commands require approval except for two exact read-only Git inspections
(`git status --short` and `git diff --check`); test runners, Python scripts, formatters,
linters, publication, destructive Git/container/database commands, deployment,
credential commands, and the Vercel MCP are not auto-approved (the latter is denied).
Approving a code-execution command still trusts the code in the checkout; run untrusted
or prompt-influenced changes only after reviewing the diff, in an isolated environment
without credentials. Safe repository reads deny
environment and credential files. The config pins
`github-copilot/gpt-5.6-luna` and
variant `medium` for `cloze-developer`. The model was found in the current installation;
each delegation confirms availability, quota, and variant. If GPT quota is exhausted,
the coordinator chooses and records an available free model before delegation; OpenCode
offers no fallback list per agent in this configuration. The primary agent coordinates
through AGENTS and can invoke profiles. Skills are allowlisted by role; confirm
effective permissions with `opencode debug config` after changes. The developer does
not delegate.

External requirements may live outside this repository in the parent workspace. The
coordinator must provide relevant requirement excerpts and source paths in each agent
assignment; subagents cannot read external directories and must not infer missing
requirements.

Git hooks install once per clone and work independently of the editor. They do not
authenticate human review: no agent can commit before human review and explicit final
content authorization.

Sources consulted: [AGENTS.md in Codex](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[OpenCode agents](https://opencode.ai/docs/agents/), and
[OpenCode configuration](https://opencode.ai/docs/config/).

## Pipeline skills

- `cloze-architect`: `domain-modeling`, `supabase`, and
  `supabase-postgres-best-practices` as scope requires.
- `cloze-developer`: `supabase` and `supabase-postgres-best-practices` for Supabase,
  SQL, migrations, RLS, and database-test changes.
- `cloze-reviewer`: `code-review-and-quality` for every review and both Supabase skills
  for relevant changes.
- `code-review` and `improve-codebase-architecture` are available only through manual
  invocation. They need additional context or permissions incompatible with the
  standard pipeline, so roles do not load them automatically.
