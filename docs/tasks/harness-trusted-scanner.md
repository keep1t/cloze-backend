# Trusted scanner and complete Git coverage

- Status: IMPLEMENTED
- Source request/plan: Authenticate Gitleaks installation and scan ref names and introduced commit ranges.
- Dependencies and evidence they are ready: Gitleaks v8.24.3 release archive checksums inspected and committed in `scripts/tool-versions.json`.
- Developer: Coordinator direct implementation; no delegated model.
- Global assignment correction round: 0

## Outcome and boundaries

- Expected behavior: Gate uses only the repository-managed Linux x64/arm64 binary, verified by archive and executable SHA-256 and exact version; scanner subprocess gets an allowlisted environment; push refs and commit ranges are scanned.
- Out of scope: Changes to Gitleaks rules or product behavior.
- Permitted files: `scripts/`, `.gitignore`, tests, README.md, MEMORY.md, and security documentation.

## Criteria and verification

| ID | Observable criterion | Method and result |
| --- | --- | --- |
| AC1 | Installer verifies checksums, archive contents, platform, and executable. | Installer tests and fresh installation — passed. |
| AC2 | Gate rejects a wrong managed version, ignores PATH shadowing, and hides parent environment. | Harness tests — passed. |
| AC3 | Push scans ref names and rejects malformed input; range detects secrets removed by a later commit. | Synthetic hook/history tests — passed. |
| AC4 | Current worktree scans clean. | `python3 scripts/security_gate.py worktree` — passed. |

## Delivery

- `python3 -m unittest discover -s tests`: 22 tests passed.
- `python3 scripts/security_gate.py worktree`: passed.
- Technical review: Bugbot found no actionable bugs; Security Review found no remaining
  findings after corrections.
- Human review/commit: pending.
