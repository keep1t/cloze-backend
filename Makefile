.DEFAULT_GOAL := help

PYTHON ?= python3
DENO ?= deno
SUPABASE ?= supabase

.PHONY: help doctor setup fmt fmt-check lint typecheck quality test-harness test-functions test-db security check check-all supabase-start supabase-stop supabase-status db-reset db-lint functions-serve function-serve migration types types-check remote-link deploy-function db-push

help: ## Show available project commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "%-22s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nVariables: FUNCTION=<kebab-case-name>, NAME=<snake_case_migration>, PROJECT_REF=<ref>, CONFIRM_REMOTE=<same-ref>, CONFIRM_RESET=cloze-backend\n'
	@printf 'db-reset and check-all reset only the local database and require CONFIRM_RESET=cloze-backend. Remote commands require an exact project confirmation.\n'

doctor: ## Verify required local tools and pinned runtime versions
	$(PYTHON) scripts/project_tools.py doctor --python "$(PYTHON)" --deno "$(DENO)" --supabase "$(SUPABASE)"

setup: doctor ## Install the verified secret scanner and Git hooks for this clone
	$(PYTHON) scripts/install_gitleaks.py
	sh scripts/install-hooks.sh

fmt: ## Format Deno source, tests, JSON and Markdown under Supabase paths
	$(DENO) fmt --config deno.json --permit-no-files supabase/functions supabase/tests

fmt-check: ## Check Deno formatting without changing files
	$(DENO) fmt --config deno.json --check --permit-no-files supabase/functions supabase/tests

lint: ## Lint Edge Function and Deno test source
	$(DENO) lint --config deno.json --permit-no-files supabase/functions supabase/tests

typecheck: ## Type-check each Deno entrypoint using its nearest deno.json
	$(PYTHON) scripts/project_tools.py typecheck --deno "$(DENO)"

quality: fmt-check lint typecheck ## Run formatting, lint and type checks

test-harness: ## Run repository tooling and security harness tests
	$(PYTHON) -m unittest discover -s tests

test-functions: ## Run Deno tests for Edge Functions (reports when none exist)
	$(PYTHON) scripts/project_tools.py test-functions --deno "$(DENO)"

test-db: ## Run local pgTAP tests (reports when none exist)
	$(PYTHON) scripts/project_tools.py test-db --supabase "$(SUPABASE)"

security: ## Scan current repository files for secrets and prohibited hardcoding
	$(PYTHON) scripts/security_gate.py worktree

check: ## Run security, quality and harness checks without starting Supabase
	$(MAKE) security
	$(MAKE) quality
	$(MAKE) test-harness

check-all: ## Run checks and reset local Supabase for full integration tests
	$(PYTHON) scripts/project_tools.py confirm-reset
	$(MAKE) check
	$(MAKE) supabase-start
	$(MAKE) db-reset
	$(MAKE) db-lint
	$(MAKE) test-db
	$(MAKE) test-functions
	$(MAKE) types-check

supabase-start: ## Start the local Supabase stack
	$(SUPABASE) start

supabase-stop: ## Stop this project's local Supabase containers and preserve volumes
	$(SUPABASE) stop

supabase-status: ## Show whether this project's local Supabase stack is running without printing credentials
	$(PYTHON) scripts/project_tools.py status --supabase "$(SUPABASE)"

db-reset: ## Reset the local database (requires CONFIRM_RESET=cloze-backend)
	$(PYTHON) scripts/project_tools.py db-reset --supabase "$(SUPABASE)"

db-lint: ## Lint the local PostgreSQL schema and migrations
	$(SUPABASE) db lint --local --level warning --fail-on warning

functions-serve: ## Serve all Edge Functions locally
	$(SUPABASE) functions serve

function-serve: ## Serve one local Edge Function (requires FUNCTION=<kebab-case-name>)
	$(PYTHON) scripts/project_tools.py serve-function --supabase "$(SUPABASE)"

migration: ## Create a migration through Supabase CLI (requires NAME=<snake_case_name>)
	$(PYTHON) scripts/project_tools.py migration --supabase "$(SUPABASE)"

types: ## Generate public-schema TypeScript types from the local database atomically
	$(PYTHON) scripts/project_tools.py types --supabase "$(SUPABASE)"

types-check: ## Verify generated public-schema TypeScript types when the artifact exists
	$(PYTHON) scripts/project_tools.py types-check --supabase "$(SUPABASE)"

remote-link: ## Link this checkout to PROJECT_REF after CONFIRM_REMOTE matches it
	$(PYTHON) scripts/project_tools.py remote-link --supabase "$(SUPABASE)"

deploy-function: ## Run checks and deploy exactly FUNCTION to the confirmed linked project
	$(PYTHON) scripts/project_tools.py deploy-function --supabase "$(SUPABASE)"

db-push: ## Dry-run then apply migrations to confirmed PROJECT_REF
	$(PYTHON) scripts/project_tools.py db-push --supabase "$(SUPABASE)"
