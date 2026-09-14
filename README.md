# Cloze Backend

Cloze backend based on Supabase and future TypeScript/Deno Edge Functions. The
architecture is local-first: images and closets remain on the device.

## Current state

The repository contains the initial harness: Supabase configuration, global agent
rules, Git controls for secrets and hardcoding, and tests for those controls. It does
not yet contain product migrations or endpoints.

The [architect → developer → reviewer](docs/development-workflow.md) pipeline has
versioned profiles in `.cursor/agents/`, independent review, and at most three
correction rounds. Architect/design produces [atomic tasks](docs/atomic-tasks.md)
with explicit contracts and verification. Developers receive one at a time. For
product code, the architect writes failing tests before the developer implements;
see [test-driven development](docs/development-workflow.md#test-driven-development).
GPT-5.6 Luna (medium) is the Codex/OpenCode first choice. If GPT quota is exhausted,
the coordinator manually selects, verifies, and records an available free model; there
is no automatic fallback. Details are in [docs/development-tools.md](docs/development-tools.md).

All persisted artifacts must be English: code/comments, tests, documentation, prompts,
task records, configuration prose, reports, and commit messages. Users may communicate
in Spanish or Portuguese. The mandatory policy is in [AGENTS.md](AGENTS.md).

Functions and methods must have one cohesive responsibility without arbitrary
line-count targets. Equal explicit inputs and dependencies must produce deterministic
behavior whenever feasible. Required time, randomness, external state, concurrency,
and I/O variation must be explicit at an appropriate boundary, bounded and validated
where applicable, and tested or documented; hidden mutable state and incidental
nondeterminism are prohibited as substitutes for a defined contract. See
[AGENTS.md](AGENTS.md), the applicable `.cursor/rules/`, and the
[development workflow](docs/development-workflow.md).

The current uncommitted harness policy delivery is
[`harness-srp-determinism`](docs/tasks/harness-srp-determinism.md). It is
technically reviewed and changes no product behavior, schema, RLS, privacy boundary,
secrets, or runtime configuration.

The current uncommitted harness policy delivery is
[`harness-tdd`](docs/tasks/harness-tdd.md). It is technically reviewed and adds
test-driven development to the pipeline.

Shared professional skills live in `.agents/skills/`; `skills-lock.json` records their
integrity. [MEMORY.md](MEMORY.md) maintains state/decisions/outstanding work; AGENTS
requires updating it with this README after every implementation.

**Do not create or amend commits before human review and explicit authorization of the
final content.** Agent approval does not replace human approval. Hooks do not
authenticate it; see [AGENTS.md](AGENTS.md).

## Set up the environment

Primary environments: **VS Code, Codex, and OpenCode**. VS Code tasks verify the
harness; OpenCode profiles are in `opencode.json`; Codex uses AGENTS and explicit
delegation. See [tool setup](docs/development-tools.md).

Requirements: Git, Python 3, Deno, Supabase CLI, and Docker for the local stack.

```sh
go install github.com/zricethezav/gitleaks/v8@v8.24.3
sh scripts/install-hooks.sh
supabase start
```

Run from the repository root. Hooks install per clone and refuse to overwrite another
`core.hooksPath`. See [.env.example](.env.example) for variable names; provide real
values only via ignored local environment or server-side secret management. Do not
publish output containing keys.

## Available verification

```sh
python3 -m unittest discover -s tests
python3 scripts/security_gate.py worktree
```

Hooks inspect the index, commit message, and pushed history. A failure or missing
dependency blocks the action. Tests verify the harness, not product functionality.
Hardcoding controls detect known patterns, not all configuration. Local hooks can be
bypassed; CI and branch protection remain pending. See [coverage and limits](docs/security-hooks.md).

## Work with agents

1. Read `AGENTS.md`, `MEMORY.md`, and this README.
2. Inspect Git state and only task-relevant files.
3. Implement and verify the change.
4. Update **MEMORY.md and README.md in the same delivery**.

Record GPT-5.6 Luna (medium) in every READY delegated task. OpenCode pins
`github-copilot/gpt-5.6-luna` with `medium`; Codex receives it during subagent
creation. Confirm availability, quota, and variant before delegation. If quota is
exhausted, record a verified free model—do not invent IDs or inherit the primary model.

Request: “Implement [objective] following the Cloze pipeline.” The coordinator loads
[role profiles](docs/development-workflow.md), keeps one developer as writer, and
requests independent review. Small changes may be implemented directly but still need
review. The workflow depends on environment delegation tools; it does not install an
autonomous executor.

Technical details are in [docs/agentic-harness.md](docs/agentic-harness.md) and
[docs/security-hooks.md](docs/security-hooks.md). Initial requirements are in parent
workspace `../docs/`; their location is recorded in memory.

The current uncommitted harness policy delivery is
[`harness-srp-determinism`](docs/tasks/harness-srp-determinism.md). It is implemented
and awaiting independent technical review; it changes no product behavior, schema,
RLS, privacy boundary, secrets, or runtime configuration.

The current uncommitted harness policy delivery is
[`harness-tdd`](docs/tasks/harness-tdd.md). It is technically reviewed and adds
test-driven development to the pipeline.
