# Automated controls

Install the pinned Gitleaks version and activate hooks in each clone:

```sh
go install github.com/zricethezav/gitleaks/v8@v8.24.3
sh scripts/install-hooks.sh
```

`pre-commit` inspects the full index, including the first commit. A correction only
in the working tree does not hide a secret that is still staged. `commit-msg` scans
the message before commit creation. `pre-push` inspects annotated tag messages and
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

These patterns are not complete semantic analysis: configurations with arbitrary names,
concatenation, and other indirect forms require review. Local hooks can be bypassed or
altered with Git; team-wide enforcement requires the same control in CI and branch
protection. There is no guarantee of detecting every secret or intercepting publication
through tools outside Git.

Manual check of tracked and new non-ignored files:

```sh
python3 scripts/security_gate.py worktree
python3 -m unittest discover -s tests
```
