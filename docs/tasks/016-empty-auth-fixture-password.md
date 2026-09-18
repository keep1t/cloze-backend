# 016 — Permit only empty `auth.users.encrypted_password` synthetic fixtures

- Status: IMPLEMENTED — independent review and human review pending.
- Source request/plan: User-authorized correction: T014's validator rejects T013's required synthetic Auth fixture solely because its `encrypted_password` column has the exact empty literal `''`.
- Dependencies: T014 remains historically REVIEWED at 3/3; T015 is separate. The T013 manifest uses one `INSERT INTO auth.users (...) VALUES (...)` fixture.
- Developer: Codex `gpt-5.6-luna` at medium reasoning, verified available in the current delegation environment.
- Global assignment correction round: 0 of 3; do not reopen/reset T014 or T015.

## Scope

- Expected behavior: accept only a constrained `auth.users.encrypted_password` identifier paired with `''`; continue rejecting all nonempty/password-like credential values and existing URL, secret, shell, psql-metacommand, and `COPY ... PROGRAM` fragments.
- Out of scope: manifest schema/protocol, process/credential handling, migrations, product-manifest edits, Make/project-tools changes, and T014/T015 history.
- Permitted files: `scripts/db_concurrency_runner.py`, `tests/test_project_tools.py`, this task, `MEMORY.md`, and `README.md`.

## Contract

- A password-like identifier is rejected unless the entire SQL field is exactly one syntactically constrained `INSERT INTO auth.users (<columns>) VALUES (<values>)` fixture: exact unquoted target, one VALUES row, no extra statement/comment/CTE/RETURNING/conflict clause; exactly one unquoted `encrypted_password` column; quote/parenthesis-aware list splitting; matching cardinality; and its value exactly `''` after whitespace only.
- Reject casts, expressions, `E''`, NULL, parameters, functions, quoted identifiers, duplicate/misaligned columns, nonempty values, and every other `password` occurrence. Retain all existing unsafe-SQL blocks.
- Implement a narrow pure helper used by `load_manifest`; it returns only pass/fail and never includes source SQL in an error.

## Verification

- Add tests accepting the exact current T013-shaped fixture and rejecting nonempty, cast, expression, NULL, omitted/duplicate/quoted/misaligned identifiers, non-`auth.users` targets, extra clauses/comments, another password-like identifier, and existing unsafe fragments.
- Run `make test-harness`, `make check`, `make test-db-concurrency`, and `git diff --check`; record actual live-run outcome without weakening validation.

| ID | Criterion | Verification | Expected result |
| --- | --- | --- | --- |
| AC1 | Exact empty synthetic Auth fixture validates | Unit/live concurrency test | Runner advances beyond manifest validation |
| AC2 | Password-like data remains rejected | Negative unit matrix | Sanitized failure for every variant |
| AC3 | Existing SQL safety blocks persist | Unit tests | Secret/URL/shell/metacommand/program rejected |
| AC4 | Scope is accurate | `make check`, diff review | Only permitted files change |

## Stop conditions

- If supporting the fixture requires another password form, arbitrary SQL grammar, or manifest/protocol/credential changes: `NEEDS_CLARIFICATION`.
- Two failed attempts for one cause: `BLOCKED`. Do not commit, push, or deploy.

## Delivery

The narrow helper is implemented in `scripts/db_concurrency_runner.py` and its
negative matrix covers an extra password occurrence in addition to malformed,
nonempty, and unsafe variants. Focused harness tests pass. The live runner now
advances beyond manifest validation and opens both sessions, then waits for a phase
marker; that protocol fault is outside T016 scope. The full harness gate is not claimed
because an existing synthetic Git-hook commit test stalls. Independent review and human
review remain pending. T014/T015 historical budgets remain unchanged.
