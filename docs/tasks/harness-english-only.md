# HARNESS-ENGLISH-ONLY - English-only repository language policy

- Status: REVIEWED (APPROVED)
- Source request: Require English throughout the repository and translate the existing Spanish harness content. Spanish and Portuguese conversation may continue, but persistent project artifacts must be English.
- Dependencies: `AGENTS.md`, `MEMORY.md`, `README.md`, the current harness documentation, and role prompts have been inspected. No runtime or product decision is required.
- Developer: coordinator, OpenCode, `github-copilot/gpt-5.6-luna` (medium); this is a bounded documentation and policy change.
- Global correction round: 0

## Outcome and boundaries

- Expected behavior: persisted repository content, including code comments, tests, documentation, agent prompts, task files, configuration prose, and commit messages, is written in English. User interaction may be Spanish or Portuguese without changing this requirement.
- Out of scope: translating third-party skills already written in English, changing identifiers/protocol literals, changing product behavior, or adding language-detection tooling.
- Permitted files: `AGENTS.md`, `MEMORY.md`, `README.md`, `.cursor/agents/`, `.cursor/rules/`, `docs/`, `.vscode/`, and this task file.
- Proposed new files: none.

## Verified context

- Read `AGENTS.md`, `MEMORY.md`, and `README.md`.
- Spanish harness documentation is present in `MEMORY.md`, `README.md`, `docs/agentic-harness.md`, `docs/atomic-tasks.md`, `docs/development-workflow.md`, `docs/development-tools.md`, `docs/security-hooks.md`, `docs/templates/atomic-task.md`, and `docs/tasks/harness-atomic-tasks.md`.
- Existing code, Edge Function rules, database rules, and installed third-party skills are already English.
- No product, API, RLS, privacy, or configuration contract changes apply.

## Implementation contract

- Translate the identified Spanish project-owned harness content into clear technical English without changing its meaning or policy requirements.
- Add a mandatory English-only artifact rule to `AGENTS.md`, with the exception that conversation may be Spanish or Portuguese.
- Ensure role prompts and workflow documentation require all task records, reports, comments, tests, documentation, and commit messages to be English.
- Keep `MEMORY.md` concise and record only actual verification and review outcomes.

## Acceptance criteria and verification

| ID | Observable criterion | Method and preconditions | Expected evidence |
| --- | --- | --- | --- |
| AC1 | Project-owned persistent content is English. | Inspect scoped files and search for common Spanish prose. | No remaining Spanish prose in scoped project-owned files. |
| AC2 | The policy requires English for artifacts while permitting Spanish/Portuguese interaction. | Inspect `AGENTS.md`, role prompts, and workflow documentation. | Clear, consistent language rule and exception. |
| AC3 | Existing harness requirements retain their meaning after translation. | Diff review and independent review. | No behavioral or security-policy regression. |
| AC4 | Documentation and task state record real verification. | Run `git diff --check` and `python3 scripts/security_gate.py worktree`. | Both checks pass. |

## Stop conditions

- If a phrase is a user-facing product contract with unclear intended English terminology, return NEEDS_CLARIFICATION with the phrase and question.
- If a translation would alter policy meaning, return NEEDS_CLARIFICATION rather than guessing.
- After two failed attempts with the same tooling cause, return BLOCKED with evidence.

## Delivery

- AC1: Translated project-owned prose in the permitted harness files. A scoped search
  for common Spanish prose markers and accented Spanish characters returned no matches.
- AC2: `AGENTS.md`, all three role prompts, and the development workflow require
  English persisted artifacts while explicitly allowing Spanish and Portuguese user
  conversations.
- AC3: Translation preserved the existing harness boundaries, including local-first
  privacy, RLS, secret/configuration controls, task readiness, independent review,
  and human authorization before commits. Independent review returned APPROVED.
- AC4: `git diff --check` and `python3 scripts/security_gate.py worktree` passed.
- Changed: `AGENTS.md`, `MEMORY.md`, `README.md`, `.cursor/agents/`,
  `docs/agentic-harness.md`, `docs/atomic-tasks.md`,
  `docs/development-tools.md`, `docs/development-workflow.md`,
  `docs/security-hooks.md`, `docs/templates/atomic-task.md`,
  `docs/tasks/harness-atomic-tasks.md`, and this task record. No new files.
- RLS, privacy, configuration, runtime behavior, identifiers, protocol literals, and
  third-party skills were not changed.
- Independent technical review returned APPROVED. Human review and commit
  authorization remain pending. No commit, publication, or deployment occurred.
