# Automated controls

Install the repository-managed Gitleaks binary and activate hooks in each clone:

```sh
python3 scripts/install_gitleaks.py
sh scripts/install-hooks.sh
```

The installer supports Linux x64 and arm64. It verifies the upstream release archive
against the committed SHA-256 value and installs only the executable under ignored
`.tools/`. The gate never searches `PATH`, checks the exact version, and invokes the
scanner with only a safe `PATH` and locale in its environment.

`pre-commit` inspects the full index, including the first commit. A correction only
in the working tree does not hide a secret that is still staged. `commit-msg` scans
the message before commit creation. `pre-push` inspects ref names, annotated tag messages and
all commits reachable from pushed tips, including files deleted by later commits and
commit messages. It does not use the working tree as a substitute for outgoing content.
This prioritizes coverage over speed and can be costly as history grows.

Gitleaks uses its built-in rules; environment configurations, exclusion comments, and
repository ignore files cannot disable them. An error or missing dependency blocks the
operation. Scanner output is captured to avoid printing secrets; the configuration
control reports only paths and categories, never the found value.

The additional control rejects credential files, env examples with values, literal
endpoints and machine paths, environment fallbacks, and literal assignments to known
operational names in code and SQL. Declarative configuration such as TOML/JSON remains
allowed and is scanned for secrets. Tests can use synthetic data but are also scanned
for secrets.

CI uses `range <base> <head>` to scan every introduced snapshot and commit message,
including secrets removed by a later commit.

These patterns are not complete semantic analysis: configurations with arbitrary names,
concatenation, and other indirect forms require review. Local hooks can be bypassed or
altered with Git. GitHub Actions runs the same checks for pull requests and pushes to
`main`; an owner/admin must activate the required `main` ruleset before remote
enforcement is guaranteed.

Configure the `main` ruleset to require pull requests and the strict, up-to-date
`security-gate` status check, with zero required approvals. Apply the rules to
administrators, configure no bypass actors, and block force pushes and branch deletion.
The required check must first appear on GitHub before selecting it in the ruleset.

Important limitation: a `pull_request` workflow and the scripts it invokes are sourced
from the PR revision. Requiring only the `security-gate` job name does not protect the
gate from a PR that edits the workflow or scanner to pass without scanning. Because
the proposed personal-repository ruleset has zero required approvals, this check is
not a tamper-resistant security boundary. Do not treat remote enforcement as complete
until an owner selects a trusted workflow/runner design or requires independent
approval for changes to the gate and its control files. This exception is unresolved.

Manual check of tracked and new non-ignored files:

```sh
python3 scripts/security_gate.py worktree
python3 -m unittest discover -s tests
```
