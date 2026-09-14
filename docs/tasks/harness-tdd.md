# harness-tdd — TDD workflow for product code

- Status: REVIEWED
- Source request/plan: User request for test-driven development workflow
- Dependencies and evidence they are ready: `harness-srp-determinism` (APPROVED), `harness-english-only` (APPROVED)
- Developer: N/A (harness policy)
- Global assignment correction round: N/A

## Outcome and boundaries

- Expected behavior (before → after): The architect writes failing tests as part of
  every READY task for product code. The developer implements to pass those tests.
  Tests are verified to fail before implementation begins. TDD applies to product
  code only (Edge Functions, migrations, RLS policies, database functions); harness
  and documentation changes are excluded.
- Out of scope: Changes to test framework, CI configuration, test runner setup.
- Permitted files (include MEMORY.md, README.md, and this record):
  - `.cursor/agents/cloze-architect.md`
  - `.cursor/agents/cloze-developer.md`
  - `.cursor/agents/cloze-reviewer.md`
  - `docs/atomic-tasks.md`
  - `docs/development-workflow.md`
  - `docs/templates/atomic-task.md`
  - `AGENTS.md`
  - `MEMORY.md`
  - `README.md`
  - `docs/tasks/harness-tdd.md`
- Proposed new files: None

## Verified minimum context

- Read AGENTS.md, MEMORY.md, and README.md.
- Relevant paths/symbols:
  - `.cursor/agents/cloze-architect.md`: architect role prompt (currently read-only, no test writing)
  - `docs/atomic-tasks.md`: task definitions and READY gate
  - `docs/development-workflow.md`: pipeline sequence (architect → developer → reviewer)
  - `docs/templates/atomic-task.md`: task template with criteria/verification section
  - `AGENTS.md`: agent workflow section describes pipeline
- Verified contracts/documentation: Existing pipeline is architect → developer → reviewer; no test-writing step exists
- Verified assumptions: Deno test framework available (`deno test --allow-env --allow-net supabase/tests`)

## Implementation contract

- Inputs, types, validation, and synthetic examples:
  - Architect produces test files in `supabase/tests/` as part of READY task
  - Tests follow Deno testing conventions (`Deno.test()`, assertion imports)
  - Tests are verified to fail against current codebase before developer starts
- Outputs/errors and edge-case behavior:
  - READY task includes test files and verification that they fail
  - Developer implements to pass the tests
  - Reviewer checks tests exist, fail before, pass after
- Authorization/RLS/privacy and required configuration: N/A (policy change only)
- Concrete ordered steps:
  1. Update `cloze-architect.md` with test-writing responsibility
  2. Update `cloze-developer.md` with TDD implementation instructions
  3. Update `cloze-reviewer.md` with test verification requirement
  4. Update `docs/development-workflow.md` with TDD sequence
  5. Update `docs/atomic-tasks.md` to require tests in READY tasks
  6. Update `docs/templates/atomic-task.md` with test sections
  7. Update `AGENTS.md` with TDD policy

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | Architect prompt includes test-writing responsibility | Read `.cursor/agents/cloze-architect.md` | Contains test-writing instructions |
| AC2 | Workflow shows TDD sequence | Read `docs/development-workflow.md` | Architect writes tests → developer implements → reviewer verifies |
| AC3 | Atomic tasks require tests for product code | Read `docs/atomic-tasks.md` | READY gate includes test files |
| AC4 | Task template has test sections | Read `docs/templates/atomic-task.md` | Test verification fields present |
| AC5 | AGENTS.md references TDD policy | Read `AGENTS.md` | TDD policy in workflow section |
| AC6 | Scoped search finds TDD references in all required files | `rg -i "tdd\|test.driven\|failing test\|tests.*before implementation\|test.*before.*code\|write.*tests.*implement\|tests.*write.*architect" AGENTS.md .cursor/agents/ docs/atomic-tasks.md docs/development-workflow.md docs/templates/atomic-task.md` | Matches in architect prompt, workflow, atomic tasks, template |
| AC7 | No product behavior, RLS, privacy boundary, secrets, or runtime configuration changed | `git diff --stat` | No changes to `supabase/functions/`, `supabase/migrations/`, `.env*`, `supabase/config.toml` |

## Stop conditions

- Missing information, code mismatch, or required scope expansion: return
  NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run:
- Changed files and MEMORY/README update:
- Outstanding work and review findings with IDs:
- Technical review status:
- Human review/commit: pending; record only actual human authorization.
