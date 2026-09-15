# Harness role permissions and test-author workflow

- Status: IMPLEMENTED
- Source request/plan: Mitigate architect/TDD contradiction and enforce role permissions.
- Dependencies and evidence they are ready: Existing role prompts and OpenCode config inspected.
- Developer: Coordinator direct implementation; no delegated model.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior: Product-code work proceeds DESIGN_READY → restricted test author → coordinator-verified failure → READY → developer; OpenCode enforces role boundaries.
- Out of scope: Product code, schemas, and runtime Supabase changes.
- Permitted files: AGENTS.md, README.md, MEMORY.md, opencode.json, `.cursor/agents/`, relevant workflow/task docs and harness tests.

## Criteria and verification

| ID | Observable criterion | Method and result |
| --- | --- | --- |
| AC1 | Test author is registered and can edit only contract tests. | `python3 -m unittest discover -s tests` — passed. |
| AC2 | Architect/reviewer are read-only; all roles deny external directories, delegation, and Vercel tools. | `opencode debug config` plus static tests — passed. |
| AC3 | Pipeline records baseline failure before READY. | Workflow/docs tests — passed. |

## Delivery

- `python3 -m unittest discover -s tests`: 22 tests passed.
- `opencode debug config`: four roles resolved and permission assertions passed.
- Technical review: Bugbot found no actionable bugs; Security Review found no remaining
  findings after corrections. Remote CI trust remains an owner decision in the separate
  GitHub gate task.
- Human review/commit: pending.
