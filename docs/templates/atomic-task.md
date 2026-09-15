# <ID> — <one observable outcome>

- Status: DRAFT | DESIGN_READY | READY | IMPLEMENTED | NEEDS_CLARIFICATION | BLOCKED | REVIEWED
- Source request/plan:
- Dependencies and evidence they are ready:
- Developer: environment, verified cost-effective model ID, and selection reason:
- Global assignment correction round:

## Outcome and boundaries

- Expected behavior (before → after):
- Out of scope:
- Permitted files (include MEMORY.md, README.md, and this record):
- Proposed new files:

## Verified minimum context

- Read AGENTS.md, MEMORY.md, and README.md.
- Relevant paths/symbols and what each provides:
- Verified contracts/documentation/API and version:
- Relevant external product requirements: coordinator-supplied excerpts and source paths (or not applicable):
- Verified assumptions; open decisions (none for READY):

## Implementation contract

- Inputs, types, validation, and synthetic examples:
- Outputs/errors and edge-case behavior:
- Authorization/RLS/privacy and required configuration:
- Test specifications (for product code): paths, coverage, verification command:
- Test author output and coordinator-verified failing command/output (required before READY):
- Concrete ordered steps:

Mark a section "not applicable" with its reason when it does not apply; do not leave
gaps that require the developer to design the solution.

## Criteria and verification

| ID | Observable criterion | Method/command and prerequisites | Expected result |
| --- | --- | --- | --- |
| AC1 | <one outcome> | <real verification> | <evidence> |

For product-code tasks, include at least one criterion verifying the test-author's
tests pass after implementation and that the coordinator recorded their expected
baseline failure before the task became READY.

## Stop conditions

- Missing information, code mismatch, or required scope expansion: return
  NEEDS_CLARIFICATION with evidence to the coordinator.
- Two failed attempts for the same cause: return BLOCKED with what was tried.

## Delivery (complete after implementation)

- Criteria met and actual evidence, commands/results, and checks not run:
- Changed files and MEMORY/README update:
- Test results: test-author's tests now pass, with command/output and pre-implementation failure evidence:
- Outstanding work and review findings with IDs:
- Technical review status:
- Human review/commit: pending; record only actual human authorization.
