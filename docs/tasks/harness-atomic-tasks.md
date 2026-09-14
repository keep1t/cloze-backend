# HARNESS-ATOMIC — task contract for cost-effective developers

- Status: REVIEWED (APPROVED after correcting R1/R2).
- Source: user request for specific/atomic tasks and Luna/free priority.
- Dependencies: existing pipeline and profiles read; no runtime changes.
- Developer: current coordinator, bounded instruction changes; implementation was not
  delegated to a cost-effective developer. Environment selection was discussed with user.
- Correction round: 0.

## Outcome and boundaries

Define one READY task contract that reduces implicit developer decisions. Scope:
profiles, AGENTS, docs/atomic-tasks.md, template, workflow, README, MEMORY, and this
record. Do not change models without a valid identifier or modify hooks, product code,
or publication permissions.

## Context and steps

Read AGENTS/MEMORY/README and existing profiles. Create policy and template; connect
architect/developer/reviewer; clarify model selection; update documentation. HTTP
inputs/outputs and RLS do not apply: this changes work instructions. No decision remains
open for the documentation contract; model selection is an independent pending decision
that blocks future developer delegation, not these rules.

## Criteria and evidence

- AC1: Template includes one objective, dependencies, verified context, files,
  contract, criteria/checks, and stop conditions. Documentation verification.
- AC2: Developer does not invent decisions and returns to coordinator when information
  is missing.
- AC3: Explicit cost-effective model selection without claiming the adapter enforces it.
- AC4: Preserve human review before commit and the maximum correction loop.
- AC5: `python3 scripts/security_gate.py worktree` passes; independent review occurs.

## Delivery

OpenCode is pinned to `github-copilot/gpt-5.6-luna` with `medium`; the model was found
by verifying `opencode models github-copilot`. Codex and OpenCode document Luna (medium)
as the first choice and a manual, verified, recorded free-model fallback when GPT quota
is exhausted. `python3 -m json.tool opencode.json`, `git diff --check`, and
`python3 scripts/security_gate.py worktree` passed. An independent reviewer returned
BLOCKED with R1/R2; independent re-review confirmed both corrections and returned
APPROVED. No commits; human authorization pending. Runtime tests were not run because
this was an instruction change.
