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

## VS Code

Existing Deno configuration is limited to functions/tests. From “Tasks: Run Task”,
run the scan, harness tests, and hook installation. There are no commit or deployment
tasks. The editor alone does not run the agent pipeline; use Codex or OpenCode through
its integration or terminal.

## Codex

Codex uses `AGENTS.md` as project instructions. The coordinator reads versioned
prompts and passes them to available subagent tools. It selects GPT-5.6 Luna (medium)
for the developer at subagent creation and records it in the READY task. If GPT quota
is exhausted, it manually selects and records an available free model; Codex receives
no repository automatic fallback. This repository does not configure native Codex role
registration or change global settings. If a session cannot delegate, report that
independent review is missing.

## OpenCode

`opencode.json` registers the three roles as subagents, reusing prompt files and
adding memory and README instructions. It pins `github-copilot/gpt-5.6-luna` and
variant `medium` for `cloze-developer`. The model was found in the current installation;
each delegation confirms availability, quota, and variant. If GPT quota is exhausted,
the coordinator chooses and records an available free model before delegation; OpenCode
offers no fallback list per agent in this configuration. The primary agent coordinates
through AGENTS and can invoke profiles; they can also be mentioned as
`@cloze-architect`, `@cloze-developer`, and `@cloze-reviewer`. Architect/reviewer lack
edit, shell, and delegation permissions; they receive coordinator evidence and read
files directly. The developer does not delegate. Additional tool permissions depend on
installation; read-only and human-review rules apply to every available tool.

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
