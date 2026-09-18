# 015 — Allow marker-free successful bootstrap and teardown phases

- Status: IMPLEMENTED — independent review and human review pending; live concurrency is now blocked by a separate phase-marker wait outside T015 scope.
- Source request/plan: User-authorized bounded correction after T014 exhausted its 3/3 correction budget. Fix the runner's marker-free bootstrap/teardown call behavior.
- Dependencies and evidence they are ready: T014 is REVIEWED. `scripts/db_concurrency_runner.py` passes `''` to `_finish` for bootstrap and teardown, while `_finish` treats every non-`None` marker as required; the first live manifest run therefore fails before opening its two sessions.
- Developer: Codex `gpt-5.6-luna` at medium reasoning, verified available in the current delegation environment.
- Global assignment correction round: 0 of 3. This is separate from T014; do not reopen or reset T014's historical budget.

## Outcome and boundaries

- Expected behavior (before → after): Successful marker-free SQL phases fail because `''` requires a missing empty marker. Bootstrap, commit, and teardown may return no scalar output; only deliberately marked phases assert a scalar result.
- Out of scope: Manifest schema, status/credential parsing, password-file behavior, process ordering, SQL-safety rules, lock/replay protocol, migrations, product tests, and changes to T014's history.
- Permitted files:
  - `scripts/db_concurrency_runner.py`
  - `tests/test_project_tools.py`
  - `docs/tasks/015-marker-free-concurrency-phases.md`
  - `MEMORY.md`
  - `README.md`

## Implementation contract

- `_finish(process, sql, expected_marker: str | None = None)` has two modes:
  - `None`: marker-free. Write SQL and `\q`, require successful process exit, return stripped output (which may be empty), and do not compare a marker.
  - A nonempty string: marker-required. Require one output line exactly equal to that marker; absence raises the existing sanitized error.
- Empty string is never marker-required. Bootstrap, A commit, and teardown pass `None`; B lock probe and B replay retain their existing nonempty markers.
- Do not weaken exit handling, output suppression, credential controls, or lock/replay assertions.

Implementation evidence: `_finish` now treats `None` as marker-free while preserving
strict nonempty marker checks. Bootstrap, A commit, and teardown pass `None`; B lock
and replay retain required markers. Mocked coverage verifies empty marker-free output,
strict marker rejection, protocol ordering, and marker arguments.

## Test and verification

- Add mocked tests proving marker-free `_finish(..., None)` succeeds with empty output; required markers remain strict; `run_manifest` passes `None` for bootstrap/commit/teardown and retains B markers; and a successful mocked manifest reaches A/B/replay with empty bootstrap/teardown output.
- Earlier verification: `make test-harness` passed (51 tests), `make check` passed (security,
  Deno format/lint/type checks, and 51 harness tests), and `git diff --check` passed.
  Its original manifest-validation blocker is resolved by T016. A later live run opens
  both sessions but waits for a `psql` phase marker; T015 excludes lock/replay protocol
  changes, so no live concurrency pass is claimed. A current full harness run also
  cannot be certified because an existing synthetic Git-hook commit test stalls.

| ID | Criterion | Verification | Expected result |
| --- | --- | --- | --- |
| AC1 | Marker-free phases succeed with empty output | Mocked tests | No unexpected-marker error |
| AC2 | Required markers remain strict | Mocked tests | Absent marker raises sanitized error |
| AC3 | Protocol remains unchanged | Asserted mocked call sequence | A create → B lock probe → A commit → B replay |
| AC4 | Scope and documentation are accurate | `make check`, `git diff --check` | Only permitted files change |

## Stop conditions

- If this requires manifest/schema/protocol/credential changes, return `NEEDS_CLARIFICATION`.
- After two failed attempts for the same cause, return `BLOCKED` with evidence. Do not commit, push, or deploy.

## Delivery

Marker-free implementation is complete, but the live verification blocker is outside
T015 scope and requires a runner-protocol correction. Independent review and human
review remain pending. T014's historical approval and correction budget remain
unchanged.
