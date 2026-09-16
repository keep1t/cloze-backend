# Cloze Backend

Cloze backend based on Supabase and future TypeScript/Deno Edge Functions. The
architecture is local-first: images and closets remain on the device.

## Current state

The repository contains the initial Supabase product schema for runtime-managed
configuration, owner-scoped user settings, and private server-managed entitlements.
No business configuration values are seeded. The migration also provisions minimal
settings rows from Auth UUIDs without copying email or user metadata. Provider setup
and environment-managed configuration keys are documented in
[Auth provider setup](docs/auth-provider-setup.md). A second migration adds an
owner-scoped garment UUID registry and private, versioned textual embeddings. It stores
neither garment images nor fixed taxonomy/model dimensions, and its externally managed
Free limit is enforced atomically on activation. Edge Function endpoints remain future
work. Private coordination primitives now support idempotency, opaque cache entries,
refresh leases, fixed-window rate limits, and bounded cleanup for those endpoints.
Private share snapshots now use an opaque token-hash lifecycle and a private Storage
bucket; Edge endpoints and signed upload/download issuance remain future work.
The confirmed integration direction is OpenWeather through server-only Edge Functions,
on-device garment classification with versioned textual attributes, rotating renewed
share tokens, and RevenueCat as the mobile subscription authority.
Edge Functions follow simplified DDD: HTTP handlers call application use cases, which
depend on repository and provider ports. Adapters own Drizzle persistence or external
HTTP details; business code never accesses Supabase or SQL directly.
The shared runtime foundation validates database URLs before creating a pinned Drizzle /
postgres client, disables prepared statements for transaction pooling, and keeps the
driver imports isolated from domain, application, and adapter composition code.

The [architect → test author → developer → reviewer](docs/development-workflow.md) pipeline has
versioned profiles in `.cursor/agents/`, independent review, and at most three
correction rounds. Architect/design produces [atomic tasks](docs/atomic-tasks.md)
with explicit contracts and verification. Developers receive one at a time. For
product code, the architect specifies tests, a restricted test author writes them,
and the coordinator records their expected baseline failure before implementation;
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

The harness uses a test-author role to keep architecture read-only while retaining
test-first implementation. OpenCode permissions are approval-default with restricted
test paths, shell controls, and external-directory protections. See
[development tools](docs/development-tools.md).

Shell commands that execute checkout code require explicit approval, but approval
still trusts that code and should only be granted after reviewing the diff (prefer an
isolated environment without credentials). The proposed `security-gate` status is also
self-modifiable from a PR; zero required approvals do not make it tamper-resistant.
See [security hooks](docs/security-hooks.md) for the outstanding trust decision.

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

Requirements: GNU Make 4.3+, Git, Python 3.11+, Deno, Supabase CLI, and Docker for the
local stack. Use the Deno and Supabase CLI versions recorded in
[`scripts/tool-versions.json`](scripts/tool-versions.json).

```sh
make doctor
make setup
```

Run from the repository root. Hooks install per clone and refuse to overwrite another
`core.hooksPath`. See [.env.example](.env.example) for variable names; provide real
values only via ignored local environment or server-side secret management. Do not
publish output containing keys.

## Development commands

Run `make help` to see the supported commands. The main checks are:

```sh
make fmt
make check
make check-all CONFIRM_RESET=cloze-backend
```

`make check` runs the security scan before format, lint, type checking, and harness
tests; it does not start Docker or Supabase. `make check-all` starts local Supabase,
resets the database from migrations and seed data, then runs database lint and
available integration tests. The reset replaces local database contents and requires
the confirmation value to match `project_id` in `supabase/config.toml`.

`make test-functions` discovers Deno tests named `test.ts`, `*_test.ts`, `*.test.ts`,
or `*-test.ts` under `supabase/tests`; if none exist, it reports an explicit skip.

Use `make supabase-start`, `make supabase-status`, and `make supabase-stop` for local
stack management. The status command reports only whether the stack is running and
suppresses URLs and credentials. `make migration NAME=create_shares` creates a
timestamped migration through the Supabase CLI. `make types` generates local public
schema types atomically; `make types-check` skips until the generated type file
exists.

Remote commands are explicit. `make remote-link` requires `PROJECT_REF` and
`CONFIRM_REMOTE` to match. `make deploy-function` deploys only the named `FUNCTION`,
requires the same confirmation and linked project, and runs `make check` first.
`make db-push` requires the exact linked reference and confirmation, performs
`supabase db push --dry-run --linked`, and only then applies migrations. None of these
commands run in CI. See [development tools](docs/development-tools.md) for the
complete command groups and CI behavior.

## Available verification

```sh
python3 -m unittest discover -s tests
python3 scripts/security_gate.py worktree
python3 scripts/security_gate.py range <base-commit> <head-commit>
```

Hooks inspect the index, commit message, pushed ref names, and all history reachable
from pushed tips. Gitleaks is installed from a pinned release checksum under ignored
`.tools/`. GitHub Actions repeats the tests and scans for pull requests and pushes to
`main`, runs `make check`, and has a separate local Supabase integration job.
Integration uses no project credentials and stops its ephemeral local stack after
the job. Checkout is pinned to v6.1.0 by full SHA for its Node 24 runtime. The `main`
ruleset still requires owner/admin configuration after the workflow is available.
Database contract tests cover account settings, configuration readers, entitlement
evaluation, garment identity/embedding privacy, grants, and Auth provisioning; hardcoding controls still detect known
patterns, not all configuration. See [coverage and limits](docs/security-hooks.md).

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

Harness implementation status and evidence live in individual
[`docs/tasks/`](docs/tasks/) records; backend quality tooling is technically reviewed,
with human review still pending. This README describes the current system.
