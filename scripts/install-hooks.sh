#!/bin/sh
set -eu
cd "$(git rev-parse --show-toplevel)"
python3 scripts/security_gate.py doctor
existing=$(git config --get core.hooksPath || true)
if [ -n "$existing" ] && [ "$existing" != '.githooks' ]; then
  echo 'Another hooksPath is configured; integrate it before installing.' >&2
  exit 1
fi
git config --local core.hooksPath .githooks
echo 'Cloze pre-commit, commit-msg and pre-push hooks installed.'
