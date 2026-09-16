# Agent development pipeline

## Roles and execution

The primary agent coordinates the workflow. Versioned definitions are in
`.cursor/agents/cloze-architect.md`, `cloze-test-author.md`, `cloze-developer.md`,
and `cloze-reviewer.md`. In OpenCode, the developer uses OpenCode Zen Big Pickle;
in Codex, it uses GPT-5.6 Luna (medium). The coordinator records the selected
environment-specific model in the task before delegation, according to
`docs/atomic-tasks.md`. If the selected model is unavailable, the coordinator
manually selects and records an available free model; there is no inheritance or
automatic fallback.

Environments that discover `.cursor/agents/` can use those profiles directly. With
generic subagent tools, the coordinator reads the role file and provides it as
instructions to the agent together with the entry paths. A filename alone does not
register a role in those tools. If delegation is unavailable, report the limitation:
self-review must not be presented as independent review. Leave that review pending.

This protocol directs the coordinator during a task; it is not a scheduler or a
background execution service. It does not create new sidebar tasks.

All persisted artifacts—code/comments, tests, documentation, prompts, task records,
configuration prose, reports, and commit messages—must be in English. This does not
restrict user conversations in Spanish or Portuguese.

## Function responsibility and deterministic behavior

All roles preserve these implementation expectations within their existing scope and
permissions; the policy does not authorize additional access or actions.

- Functions and methods own one cohesive responsibility. Extract code only when a
  responsibility is independently meaningful or testable, not to meet an arbitrary
  line-count target.
- Equal explicit inputs and dependencies produce deterministic behavior whenever
  feasible.
- Necessary variation from time, randomness, external state, concurrency, and I/O is
  explicit at an appropriate boundary, bounded and validated where applicable, and
  tested or documented as observable behavior. Hidden mutable state and incidental
  nondeterminism do not substitute for a defined contract.

Architects specify these boundaries and evidence in DESIGN_READY tasks. Developers implement
them without expanding the accepted scope. Reviewers verify them when relevant to the
task and report concrete defects without changing files.

## Minimum assignment input

Architect/design supplies atomic records using the [template](templates/atomic-task.md).
The coordinator stores them in `docs/tasks/` and validates the READY gate in
[atomic-tasks.md](atomic-tasks.md). Each developer receives one record, not a broad
goal. For small changes, the coordinator writes the same minimum specification.

- User-authorized objective and scope.
- Role, repository directory, and paths for `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Coordinator-provided excerpts and source paths for relevant product requirements
  held outside the repository; subagents do not access external directories.
- Plan/acceptance criteria and relevant files.
- Work baseline: Git state and prior changes that must be preserved.
- Write permissions, existing evidence, and correction-round number.

The coordinator also inspects new files: this repository can contain untracked files
that do not appear in `git diff`. There is no need to read the entire codebase.

## Test-driven development

For product code (Edge Functions, migrations, RLS policies, database functions),
the architect specifies tests, a restricted test author writes them, and the
coordinator verifies their expected failure before the developer implements. The
developer's job is to make those tests pass, not to write tests from a separate specification.

1. **Architect** returns DESIGN_READY with test paths, coverage, and verification
   command; it does not edit or run commands.
2. **Test author** writes only the specified tests in `supabase/tests/`. It cannot
   run commands. The coordinator runs them against the unchanged baseline and records
   actual failure evidence; only then does the task become READY.
3. **Developer** implements the solution and runs contract tests until they pass.
   The developer does not modify those test files unless a contract change returns to design.
4. **Reviewer** checks that tests existed before implementation, fail before and
   pass after, and cover the acceptance criteria.

TDD applies to product code only. Harness, documentation, and configuration
changes follow the standard architect → developer → reviewer sequence without
the test-writing step.

## Sequence and loop

1. **Coordinator:** bounds the assignment and records the initial state. Use the
   full workflow for contracts, schema, authorization, or architecture. For clear,
   small documentation/configuration changes, define brief criteria and send them
   directly to the developer; record the reason.
2. **Architect:** delivers a read-only `DESIGN_READY` plan with test specifications
   for product code. `NEEDS_DECISION` stops dependent work.
3. **Test author:** writes specified tests for product code; the coordinator records
   expected-failure evidence before marking the task READY. Harness-only tasks skip it.
4. **Developer:** implements to pass contract tests, verifies, and updates
   memory and README. For small changes, the coordinator may take this role while
   retaining an independent reviewer.
5. **Independent reviewer:** inspects the delivery and evidence. Does not edit.
6. **Correction:** `CHANGES_REQUESTED` returns to the developer with concrete IDs;
   then it is reviewed again. A contract change returns to the architect.
7. **Closure:** only with `APPROVED`, fulfilled criteria, required passing checks,
   and coherent documentation. The coordinator consolidates review evidence in
   memory and delivers the result to the user.
8. **Human review before commit:** deliver the final uncommitted set, including
   documentation, diff/new files, and evidence. Create or amend commits only after
   the human reviews and explicitly authorizes that content. Reviewer `APPROVED` is
   technical validation, not human authorization. Prior approval does not cover new
   changes. Authorization does not include push/deployment or allow skipped controls.

A delivery can be technically ready while awaiting human review for commit. Current
hooks scan content but do not certify human review; the agent protocol imposes this
requirement.

Allow at most **three correction rounds after initial review**, including redesigns
and new delegations; never reset the counter to extend the loop. If a blocking finding
persists, indispensable evidence is missing, or an out-of-scope decision is needed,
record the state and request the concrete intervention. Resolve recoverable in-scope
operational failures before escalation. Do not declare approval because rounds ended.

## Coordination and evidence

- Only one writer works at a time; architect/reviewer are read-only and the test author
  may edit only task-permitted test files. The coordinator does not edit while a role
  writes. All roles can share the filesystem.
- The reviewer is a distinct instance from the implementer. Do not treat its own
  assessment as independent approval: provide criteria, paths, diff, and evidence.
- The developer updates MEMORY/README for every implementation. The reviewer checks
  both. The coordinator only adds closing review/verification facts; substantive later
  changes require another relevant review.
- Approval requires zero blocking findings. Optional suggestions can remain pending
  when they do not prevent the criteria from being met.
- Roles do not expand permissions: no push, deployment, remote changes, or destructive
  operations just because the workflow is active.
- Skills in `.agents/skills/` are shared by Codex and OpenCode. The architect uses
  `domain-modeling` and two Supabase skills for database design; the developer uses
  Supabase skills for implementation; the reviewer always uses
  `code-review-and-quality` and Supabase skills where relevant. Manual skills do not
  replace the pipeline or expand permissions.
- Git hooks remain mandatory. Agents cannot disable them or treat human/reviewer
  approval as a substitute for scanning.
- Keep a concise task state, round, pending findings, and next action in memory when
  interrupted. Consolidate after completion; do not store full transcripts or secrets.

## Invocation example

“Implement [objective] following the Cloze pipeline. Use repository profiles, define
acceptance criteria, request independent review, resolve findings within the round
limit, and update MEMORY.md and README.md on closure.”
