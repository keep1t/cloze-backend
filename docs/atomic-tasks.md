# Atomic tasks and model selection

The architect (or solution designer) must resolve decisions and divide work before
delegation. A task has one observable outcome, a closed contract, and its own
verification; it is never “implement the entire backend” or a list of independent
goals. It need not correspond to a commit.

## DESIGN_READY and READY gates

The coordinator materializes the architect's read-only plan in
`docs/tasks/<id>.md` using [the template](templates/atomic-task.md). For small changes
it may write the record directly, but must not omit it. `DESIGN_READY` means design
decisions are resolved; it is not permission to start implementation. Verify:

- One outcome and explicit scope, with completed or available dependencies.
- Existing paths/symbols confirmed; new ones labeled proposed.
- Input/output contracts, errors, and edge cases defined. APIs and versions are
  supported by verified code or documentation, not model memory.
- Permitted files and sufficient minimum context. Include memory, README, and the
  task record in documentation scope; the developer does not receive full history.
- Numbered criteria and expected evidence: success, rejection, and authorization
  where applicable. Commands and prerequisites are verified; do not demand fictional tests.
- No unresolved product, security, or architecture decision is in scope.
- For product code tasks, delegate test creation to `cloze-test-author`, restricted
  to permitted `supabase/tests/` paths. The coordinator runs tests against the
  unchanged baseline and records command/output showing the expected failure. Only
  then mark the task READY and delegate implementation.

If there are multiple outcomes, independent contexts, or open decisions, split the
task or return it to design. Do not separate a migration from its RLS policies or
leave an insecure intermediate delivery to meet a file quota. Atomicity means cohesion
and verification, not an arbitrary line limit.

## Cost-effective developer

The default developer model is **OpenCode Zen Big Pickle** in OpenCode and
**GPT-5.6 Luna (medium)** in Codex. The coordinator explicitly selects the
environment-specific model and records its identifier, environment, and selection
reason in the task. Verify it is available before delegation. Do not call a model
cost-effective from its name alone.

Do not silently inherit a costly model. If GPT-model quota is exhausted, the
coordinator explicitly selects an available free model, verifies its current ID, and
documents the change and reason in the task before delegation. There is no automatic
fallback: do not invent IDs or change provider/credentials. Architect and reviewer
need not use the developer's model.

In Codex, supply GPT-5.6 Luna (medium) when creating the subagent with a self-contained
assignment. In OpenCode, `agent.cloze-developer.model` pins
`opencode/big-pickle` without a variant. Verify it through
`opencode models opencode --verbose`; availability and its zero-cost metadata must be
reconfirmed before each delegation. Record the effectively chosen model when using a
free fallback.

The developer executes one READY record at a time. Before editing, it compares files
and preconditions with the assignment. For nonexistent symbols, ambiguous contracts,
missing dependencies, or scope expansion, return `NEEDS_CLARIFICATION` with evidence
and the smallest question. Do not invent APIs, endpoints, variables, test results, or
product behavior. Local details covered by verified conventions may be resolved.

After two failed attempts for the same cause, return `BLOCKED` with what was tried;
the coordinator clarifies or narrows the task. A switch to a more capable/costly model
must be explicit and justified, never automatic. Preserve the pipeline's global
three-correction-round count; do not reset it by splitting tasks.

## Delivery and review

The developer returns a criterion-by-criterion summary with evidence, modified files,
uncertainties, and a status (`IMPLEMENTED`, `NEEDS_CLARIFICATION`, or `BLOCKED`).
`IMPLEMENTED` is not technical or human approval. Update the task, memory, and README;
the reviewer compares the result with the task and checks scope did not expand. The
coordinator keeps only active task IDs/paths and status in memory. Do not duplicate
task records there. Human authorization remains required before project commits.

For product code tasks, the developer's delivery must include the test results:
the test-author's tests now pass, with the command and output as evidence. The reviewer
verifies tests existed before implementation and cover the acceptance criteria.
