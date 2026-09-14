# HARNESS-SRP-DETERMINISM - Function responsibility and deterministic behavior policy

- Status: REVIEWED (APPROVED)
- Source request: Reinforce the single-responsibility principle for functions and methods, and require deterministic behavior whenever possible.
- Dependencies: `AGENTS.md`, shared rules, role prompts, workflow, README, and MEMORY.md have been inspected. No product or runtime decision is required.
- Developer: coordinator, OpenCode, `github-copilot/gpt-5.6-luna` (medium); this is a bounded policy and documentation change.
- Global correction round: 0

## Outcome and boundaries

- Expected behavior: functions and methods have one cohesive responsibility; deterministic behavior is the default when feasible; required variation is explicit, bounded, and testable.
- Out of scope: refactoring product code, adding lint rules, selecting a clock/randomness library, or changing Edge Function runtime behavior.
- Permitted files: `AGENTS.md`, `MEMORY.md`, `README.md`, `.cursor/agents/`, `.cursor/rules/`, `docs/`, and this task file.
- Proposed new files: none.

## Verified context

- Read `AGENTS.md`, `MEMORY.md`, `README.md`, shared rules, role prompts, and the development workflow.
- Existing Edge Function guidance requires idempotency for retrying handlers but does not define single responsibility or deterministic behavior.
- No product code, API contract, database schema, RLS, privacy, secret, or configuration change applies.

## Implementation contract

- Require a function or method to own one cohesive responsibility and extract only when the responsibility becomes independently meaningful or testable.
- Require deterministic output for equal explicit inputs and dependencies whenever feasible.
- Require time, randomness, external state, concurrency, and I/O variation to be explicit at an appropriate boundary, validated where applicable, and covered by tests or documented behavior.
- Prohibit hidden mutable state and incidental nondeterminism as substitutes for a defined contract.
- Apply the policy to architect planning, developer implementation, and reviewer checks without expanding role permissions.

## Acceptance criteria and verification

| ID | Observable criterion | Method and preconditions | Expected evidence |
| --- | --- | --- | --- |
| AC1 | Repository rules require cohesive single responsibility for functions and methods. | Inspect `AGENTS.md` and `.cursor/rules/core.mdc`. | Explicit implementation guidance without a rigid line-count rule. |
| AC2 | Repository rules prefer determinism and make unavoidable variation explicit. | Inspect `AGENTS.md` and `.cursor/rules/edge-functions.mdc`. | Explicit treatment of time, randomness, external state, concurrency, and I/O. |
| AC3 | Role prompts and workflow enforce the policy during design, implementation, and review. | Inspect all role prompts and workflow documentation. | Consistent role-specific checks. |
| AC4 | Documentation and memory record actual evidence. | Run `git diff --check` and `python3 scripts/security_gate.py worktree`. | Both checks pass. |

## Stop conditions

- If a rule would require selecting a runtime dependency or product behavior, return NEEDS_CLARIFICATION.
- If a translation or policy statement would weaken existing security, privacy, RLS, or configuration requirements, return NEEDS_CLARIFICATION.
- After two failed attempts with the same tooling cause, return BLOCKED with evidence.

## Delivery

- Implemented the cohesive-function-responsibility and deterministic-behavior policy
  in the global instructions, applicable rules, all three role prompts, and the
  development workflow. The policy prohibits arbitrary line-count targets, hidden
  mutable state, and incidental nondeterminism; it requires explicit, bounded and
  validated-as-applicable, testable or documented sources of variation.
- Verification: `git diff --check` and `python3 scripts/security_gate.py worktree`
  passed. A scoped policy search confirmed the required terms in `AGENTS.md`, both
  applicable rules, all role prompts, and `docs/development-workflow.md`.
- No product, schema, API, RLS, privacy, secret, or runtime configuration behavior
  changed. Independent technical review returned APPROVED. Human review and explicit
  commit authorization remain pending; no commit was created.
