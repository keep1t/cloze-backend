# 014 — Run credential-safe local two-session database concurrency tests

- Status: REVIEWED (independent technical review APPROVED after correction round 3/3; human review pending). The later live T013 manifest reaches both sessions but waits for a phase marker; T014's correction budget is exhausted, so that runtime defect needs a separate task.
- Source request/plan: User-authorized prerequisite for T013 AC8. Provide an isolated local-only runner that verifies PostgreSQL concurrency with two real sessions without storing or printing credentials.
- Dependencies and evidence they are ready: The local Supabase stack and host `psql` are available. T013's pgTAP suite passes; its AC8 live proof is pending because the runner waits for a phase marker after opening its two sessions. A read-only check confirmed that `dblink` is available but uninstalled; reversible local probes showed its same-database connection requires a password/GSSAPI, so it is rejected.
- Developer: Codex `gpt-5.6-luna` at medium reasoning, verified available in the current delegation environment; selected by the repository's required cost-effective model policy.
- Global assignment correction round: 3 of 3 (all correction rounds completed).

## Outcome and boundaries

- Expected behavior (before → after): Before, `make test-db` runs SQL tests through one session and cannot prove advisory-lock behavior. After, `make test-db-concurrency` runs declared, local-only manifests through two independent PostgreSQL sessions and verifies lock exclusion plus replay after release, without exposing a database URL or password.
- Out of scope: Product schema/functions, Supabase remote projects, migrations, Edge Functions, `dblink`, production configuration, CI secrets, test credentials, changes to existing pgTAP behavior, and T013's business assertions.
- Permitted files:
  - `Makefile`
  - `scripts/project_tools.py`
  - `scripts/db_concurrency_runner.py`
  - `tests/test_project_tools.py`
  - `docs/tasks/014-local-db-two-session-concurrency-harness.md`
  - `MEMORY.md`
  - `README.md`
- Added files:
  - `scripts/db_concurrency_runner.py`
  - `supabase/tests/database/concurrency/.gitkeep`

Implementation evidence: `scripts/db_concurrency_runner.py` captures `supabase status
--output json`, validates a loopback PostgreSQL URL in memory, creates a temporary
0600 password file, and invokes directly resolved `psql` sessions with scrubbed
environments and stdin-only SQL. `make test-db-concurrency` is integrated immediately
after `make test-db` in `check-all`; an empty manifest directory reports an explicit
skip. Correction rounds 1 and 2 add deterministic scalar-marker extraction,
  metacommand/`COPY ... PROGRAM` rejection, nonce-generated lock markers that cannot be
  spoofed by manifest SQL, and a strict `lock_expression`/`lock_input` declaration for
  the T013 owner/operation `hashtextextended` key. Mocked process, ordering, direct
  invocation, argv redaction, permissions, cleanup, and sanitized-failure coverage is
in `tests/test_project_tools.py`.

Later live evidence: after T015 and T016 resolve marker-free phase handling and the
strict empty Auth fixture respectively, `make test-db-concurrency` validates the
manifest and opens both sessions. It then waits indefinitely for a phase marker. This
does not alter the historical T014 review or correction budget; it identifies the next
runner-protocol task.

## Verified minimum context

- Read `AGENTS.md`, `MEMORY.md`, `README.md`, `docs/development-workflow.md`, `docs/atomic-tasks.md`, `Makefile`, and `scripts/project_tools.py`.
- `scripts/project_tools.py` already captures subprocess output for sensitive operations and `make test-db` owns the local database test entry point.
- Supabase CLI supports `supabase status --output json`; implementation must verify its actual structure without printing the result. PostgreSQL `dblink` is rejected because local probes require credentials in SQL.
- This is harness-only work, so test-first product-code authoring does not apply. Unit tests under `tests/` are required before delivery.

## Implementation contract

- Add `make test-db-concurrency`, delegated by `scripts/project_tools.py`; add it to `check-all` immediately after `make test-db`.
- The runner invokes `supabase status --output json` with captured output, extracts only the local database URL in memory, and validates PostgreSQL scheme plus loopback-only host. It never logs, returns, serializes, or passes the URL in command arguments.
- Create a `0600` `PGPASSFILE` inside an OS temporary directory. Invoke a locally resolved `psql` directly, never through a shell, with a scrubbed child environment containing only `PATH`, locale settings, and `PGPASSFILE`. Remove the password file and directory in `finally`, including failures.
- Discover only JSON manifests under `supabase/tests/database/concurrency/`. Validate a strict fixed schema and filename allowlist: no credentials, URLs, shell fragments, path traversal, unknown fields, or secret-like keys. SQL is passed to `psql` through standard input only.
- Require the manifest to declare `lock_expression: owner_operation_hashtextextended_v1` and `lock_input: {{USER_ID}}:{{OPERATION_ID}}`; the runner generates that exact owner/operation advisory-lock probe and validates its false result with an internal nonce marker.
- The generic protocol is deterministic and has no sleeps, polling, or hardcoded timeouts: bootstrap fixtures; start session A in a transaction and invoke the manifest creation SQL under `service_role`; session B probes the manifest-declared, validated advisory-lock expression through generated `pg_try_advisory_xact_lock`, which must yield false; commit A; then session B invokes replay SQL in a new transaction and checks the declared scalar marker. Teardown deletes only the manifest's synthetic fixture user.
- Capture child output only for scalar marker comparison. Convert every subprocess, parsing, or SQL failure to a sanitized diagnostic with no raw output/URL/password.
- Add a minimal smoke manifest only after an existing reviewed database primitive can prove the generic protocol. Do not add a T013-specific manifest until T013 is READY; the directory may be empty and report an explicit skip.

## Verification

- Unit tests in `tests/test_project_tools.py` must mock subprocess/filesystem behavior and cover malformed/missing/non-loopback URLs, status parsing, no-shell invocation, command redaction, strict manifest/path validation, process order, lock false/replay marker behavior, `0600` password-file permissions, and cleanup on success/failure.
- Verification run: `make test-harness` and `make check` passed (49 tests; Deno format,
  lint, and type checks passed). `git diff --check` passed. The mocked run reports one
  synthetic manifest pass; no live concurrency pass is claimed because the repository
  manifest directory remains empty.

| ID | Observable criterion | Method | Expected result |
| --- | --- | --- | --- |
| AC1 | Runner never emits or persists credentials | Unit tests and code review | Sanitized errors; URL/password never in source, arguments, or output |
| AC2 | Only local database targets are accepted | Unit tests | Non-loopback/malformed URL fails before session creation |
| AC3 | Two independent sessions use deterministic ordering | Mocked process tests | A create → B lock probe false → A commit → B replay |
| AC4 | Manifest execution cannot run arbitrary shell/config | Unit tests | Strict schema/path rejection and stdin-only SQL |
| AC5 | Existing checks remain integrated | `make test-harness`, `make check` | Pass; `check-all` calls the new target after database tests |
| AC6 | Documentation accurately records the new harness | Diff/review | T013 remains blocked until its own manifest is added and tested |

## Stop conditions

- If local Supabase status cannot provide a non-secret, in-memory-only way to acquire a loopback database connection, or the runner would require a committed credential, remote connection, SQL extension, sleep, or shell command: return `NEEDS_CLARIFICATION`.
- After two failed attempts for the same cause, return `BLOCKED` with evidence.
- Do not commit, deploy, link a remote project, or print credentials.

## Delivery

Implementation and unit-test evidence are complete after three correction rounds.
Independent technical review is APPROVED; human review remains pending. No commit,
deployment, or publication is authorized.
