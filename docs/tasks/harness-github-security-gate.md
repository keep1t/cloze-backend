# GitHub security gate

- Status: IMPLEMENTED LOCALLY; REMOTE ENFORCEMENT PENDING
- Source request/plan: Add minimal-permission CI scanning pull requests and pushes to main.
- Dependencies and evidence they are ready: Local verified scanner and test suite pass.
- Developer: Coordinator direct implementation; no delegated model.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior: A unique `security-gate` job checks full history, installs the checksum-verified scanner, runs harness tests, scans the worktree, and scans the base-to-head range.
- Out of scope: Supabase deployment and product CI.
- Permitted files: `.github/workflows/security-gate.yml`, README.md, MEMORY.md, and security documentation.

## Criteria and verification

| ID | Observable criterion | Method and result |
| --- | --- | --- |
| AC1 | Workflow runs on PRs to main and pushes to main with contents-read permission only. | YAML parsed and job/permission checked — passed. |
| AC2 | Workflow pins checkout by full commit SHA, checks full history, and runs all required local gates. | Workflow inspection — passed. |
| AC3 | Required check succeeds in GitHub and main ruleset is active. | Not verified: workflow is uncommitted/unpublished and current GitHub credentials lack repository-administration access. |

## Delivery

- 22 harness tests, local gate checks, YAML parsing, and workflow static checks passed; no GitHub Actions run was possible before publication.
- Required owner/admin action remains: activate a main ruleset requiring PRs and the strict `security-gate` check, zero approvals, administrator enforcement, no bypass actors, and blocked force pushes/deletion.
- Technical review: Bugbot found no actionable bugs. Security Review confirmed the
  documented PR-workflow tampering risk is an unresolved owner decision, not a closed
  security control.
- Human review/commit: pending.
