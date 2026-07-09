# Top-down contractor (spec-first)

Implementation of a decided design: the top model does the hard part inline
(reading the load-bearing files, writing precise specs), mid-tier agents
execute, the orchestrator verifies independently.

## Stage design

| Stage | Who | Notes |
|---|---|---|
| Scout + spec | orchestrator, inline | READ the chokepoint files yourself before writing the spec — spec precision determines the executor tier |
| Execute | sonnet (idiom-following work) / opus (framework-internals, subtle-failure parts) | usually the Agent tool, not Workflow — few agents, rich prompts |
| Verify | orchestrator, inline | run the suite/typecheck yourself; never accept the agent's summary |

## Writing the spec

The spec is the deliverable of the smart stage. It must contain:

1. **Verified context, labeled as trusted** — "CONTEXT (verified facts): ..."
   with exact file paths, line numbers, and existing idioms to copy. Every
   fact you verified yourself is a search the executor doesn't botch.
2. **Exact names** — new files, functions, columns, action strings. Naming is
   a design decision; don't delegate it.
3. **The idiom to follow** — point at the sibling code that already does it
   right ("mirror the handlers at lines 82/110", "follow the
   test_metrics_actions.py parsing pattern").
4. **The verification command** — the exact test/typecheck invocation, and
   "ALL must pass, including pre-existing."
5. **Hard boundaries** — files not to touch, servers not to start, no commits
   (unless intended). State them; agents inherit no session memory.
6. **A RETURN contract** — what the completion report must contain (files +
   line refs, test output tail, deviations with reasons). Deviations-with-
   reasons is where good agents surface discoveries (e.g. a third unaudited
   route you didn't know about) instead of silently improvising.

Rule of thumb: a precise spec drops the executor one tier. If you cannot
write the spec without hedging, the design isn't decided — go to judge-panel,
or do it inline.

## Sequencing

- **Split by file ownership.** Two agents editing one file race — even in
  "different regions". Same file → same agent, or sequential stages.
- **API-producer before API-consumer.** If stage B consumes a signature stage
  A introduces, run A first even when files are disjoint.
- Parallel contractor agents are fine when file sets AND interfaces are
  disjoint; use `isolation:'worktree'` only if they must mutate shared files.

## Verification & escalation

- Re-run the full suite yourself after each stage; verify between sequential
  stages, not just at the end (a broken stage A poisons stage B's baseline).
- Two failed verifications at a tier → re-dispatch one tier up with the
  failure evidence pasted into the prompt. Never same-tier same-spec retries.
- Read the agent's "deviations" section carefully — it is simultaneously
  where scope creep hides and where real discoveries surface.

## Failure modes

- **Spec-by-summary** — writing the spec from a report/review instead of the
  code. Reviews compress; the 20 minutes re-reading chokepoints routinely
  changes the tier decision or the design.
- **Trusting "done"** — agents report success sincerely and wrongly.
  Independent verification is non-negotiable.
- **Over-delegation of judgment** — if the executor must make a design call
  mid-task, the spec was incomplete; expect a coin-flip.
