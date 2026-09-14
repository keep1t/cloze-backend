# Agentic development harness

## Objective

Give people and agents a repeatable way to change the Cloze backend without losing
the privacy, security, and cost boundaries of the local-first product.

## Source of truth

- Product requirements: `../docs/requisitos_funcionales.md.txt` and
  `../docs/requisitos_no_funcionales.md.txt`.
- Agent operating instructions: `AGENTS.md`.
- Context-specific editor rules: `.cursor/rules/`.
- Entry point for people and agents: root `README.md`.
- Summarized state, decisions, and evidence: root `MEMORY.md`.

## Memory and mandatory closure

Every agent starts with `AGENTS.md`, `MEMORY.md`, and `README.md`, checks Git state,
and uses the memory map to limit reading to the affected area. Memory is a snapshot
to verify when work depends on it, especially for runtime facts, installations, and
deployments.

After every implementation, update both files in the same delivery: memory for
state/evidence/outstanding work and README for capabilities/usage/configuration. If
usage did not change, README reflects the concrete result in its current state. An
implementation is not complete without this update. On interruption, record what is
incomplete and how to continue. Read-only questions do not require artificial edits.

Keep memory below roughly 150 lines, consolidate obsolete information, and link to
details. Never store secrets or transcripts. Agent rules enforce this procedure;
current hooks do not evaluate documentation's semantic accuracy.

## Initial structure

```text
supabase/
  config.toml                 # Local runtime; does not auto-expose new tables
  migrations/                 # One SQL migration per schema change
  functions/
    _shared/                  # Reusable utilities without endpoint logic
    <function-name>/
      index.ts
      deno.json               # Isolated, pinned dependencies per function
  tests/                      # Deno tests separate from functions
```

## Delivery cycle

1. Bound the requirement, input/output data, and authorization model.
2. For schema changes, create the migration with `supabase migration new <name>` and
   add RLS/policies within it.
3. For endpoints, create the kebab-case function, its `deno.json`, and tests.
4. Run the local stack and `AGENTS.md` checks.
5. Document new environment variables in `.env.example` without real values.
6. Update `MEMORY.md` and `README.md` with the result and actual evidence before closure.

## Decisions already made

- `api.auto_expose_new_tables = false`: Data API exposure must be intentional and is
  separate from RLS.
- Edge Functions use TypeScript/Deno and one Deno configuration per function to avoid
  version coupling.
- The first AI integration receives UUIDs, embeddings, and garment descriptions; no
  physical images or PII.

## Outstanding work before product development

- Strict global policy: `.cursor/rules/secrets-and-configuration.mdc` and `AGENTS.md`
  prohibit publishing secrets and hardcoding operational/business configuration.
  Declarative local values in `supabase/config.toml` remain explicit configuration.
- Git hooks in `.githooks/` block commits and pushes for findings or scanner errors.
  Installation, coverage, and limitations are in [security-hooks.md](security-hooks.md).
  Each clone must install them; CI/branch protection are still absent, and `.gitignore`
  does not protect already tracked files or history.
- Link the remote Supabase project and confirm its Postgres version.
- Design the first data/authorization model for embeddings/outfits, including RLS evaluation.
- Define the first recommendation Edge Function contract and deployment variables.
