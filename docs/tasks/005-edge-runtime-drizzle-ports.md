# 005 — Edge runtime ports and Drizzle compatibility

- Status: REVIEWED
- Source: confirmed simplified DDD/adapters/repository architecture.
- Dependencies: T01–T04 reviewed; no provider endpoint is included.
- Developer: coordinator implementation after the recorded test-first baseline.

## Outcome and boundaries

Provide a Deno-compatible shared Edge runtime where handlers depend only on application
use cases and ports, persistence adapters implement repository ports with Drizzle, and
external adapters remain replaceable. This task validates imports/configuration only; it
does not connect to a remote database, deploy a function, add an endpoint, or change SQL
migrations.

## Contract

- Add `_shared/domain/` port and result/error types, `_shared/application/` use-case
  invocation boundary, `_shared/adapters/` composition boundary, and `_shared/db/` only
  for Drizzle construction. Handlers/use cases may not import Supabase clients, `postgres`,
  Drizzle, `Deno.env`, or provider fetch implementations.
- Use pinned `npm:drizzle-orm@0.45.2` and `npm:postgres@3.4.9` only in the DB adapter.
  The adapter accepts a validated database URL, uses transaction-pool-safe `prepare: false`,
  and exposes an explicit close operation. It must not execute queries during import.
- Configuration validates required values when the adapter is constructed, fails closed
  with an error naming a key but never its value, and never logs secrets.
- Each future Edge Function owns a `deno.json`; this task provides a shared import map or
  dependency configuration without unpinned remote imports.
- Tests must demonstrate architectural import boundaries, deterministic configuration
  failure, no import-time I/O, Deno type checking, and construction with an injected URL.

## Test-first contract

The restricted author may edit only `supabase/tests/shared/edge_runtime_drizzle_test.ts`.
It must fail before runtime modules exist and then cover the stated isolation/configuration
contracts. Verify with `make test-functions` and `make check`.

## Stop condition

If Deno cannot type-check the pinned Drizzle/postgres driver, return BLOCKED with the
compiler evidence; do not substitute a direct Supabase client or unverified driver.

## Delivery

- Baseline/evidence: the original five-test contract was authored before the shared runtime modules and failed on their missing imports. After implementation, `make test-functions` passes 8 tests, `deno check --config deno.json supabase/functions/_shared/db/database.ts` passes, and `make check` passes its 40-test harness. Reviewer-correction regressions cover URL validation before factory invocation, result/composition contracts, and source-level boundaries.
- Technical review: APPROVED. The independent reviewer verified validation before construction, pinned/locked dependencies isolated in `db/deps.ts`, `prepare: false`, explicit close, and read-scoped static boundary coverage.
- Human review/commit: pending.
