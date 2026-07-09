---
name: orchestration
description: Catalog of multi-agent orchestration topologies (pyramid, top-down contractor, judge panel, adversarial, escalation ladder, loop-until-dry) with model-tier guidance per stage. Load BEFORE designing any Workflow script or multi-agent dispatch to pick the topology and cost shape deliberately.
---

# Orchestration topologies

This file is the CHOOSER. Each topology has a detailed reference in
`references/<name>.md` — stage tables, tier guidance, prompt templates,
workflow skeletons, and failure modes. Flow: pick from the catalog below,
then READ the matching reference before designing the stages:

- `references/pyramid.md` · `references/contractor.md`
- `references/judge-panel.md` · `references/adversarial.md`
- `references/escalation-ladder.md` · `references/loop-until-dry.md`
(No reference for the null topology — if you picked it, stop orchestrating.)

The master question is never "what abstraction level is this stage" — it is:
**where does an uncaught error become irrecoverable?** Place the smartest
model there. Place the cheapest models wherever errors are caught by a
downstream stage (validators, tests, judges, the orchestrator's own review).
Cost tiering follows the error-recovery topology, not the abstraction stack.

Second question: **what does the wide stage produce?** If it produces *facts*
(file reads, inventories, classifications), wide can be cheap — facts are
checkable. If it produces *judgment or design* (candidate solutions,
architectures, plans), wide must be smart — a weak candidate pool caps the
outcome no matter how good the downstream judge.

## The topologies

### 1. Pyramid / map-reduce (bottom-up)
Cheap wide fan-out reads → mid/high verification → one top-model synthesis.
- **Fits:** audits, code indexing, research sweeps, migrations-with-verify —
  leaf work is easy, parallel, and verifiable.
- **Tiers:** fan-out haiku/sonnet `effort:'low'`; verify opus `effort:'high'`
  (or 3+ sonnet majority vote); synthesis top model, exactly one, empowered to
  re-read disputed sources and overrule.
- **Failure mode to guard:** validators rubber-stamping. Prompt them to refute.

### 2. Top-down contractor (spec-first)
Top model reads the key files itself and writes precise specs → mid-tier
agents execute → orchestrator (or tests) verifies.
- **Fits:** implementation work. The irrecoverable error is a wrong design;
  execution errors are caught by tests/typecheck.
- **Tiers:** spec = inline top model (writing the spec IS the hard work);
  execution = sonnet if the spec names files/idioms/tests, opus for
  framework-internals or subtle-failure parts; verification = orchestrator
  runs the suite itself, never trusts the agent's summary.
- **Rule of thumb:** a precise spec drops the executor one tier. If you can't
  write the spec, the tier is higher than you think — or you need topology 5.

### 3. Judge panel / tournament
N strong, deliberately diverse attempts (different angles: MVP-first,
risk-first, user-first) → judges score against a rubric → synthesis grafts
the best ideas from runners-up onto the winner.
- **Fits:** design problems, API shapes, architecture choices, naming — wide
  solution spaces where one-attempt-iterated gets stuck in a local optimum.
- **Tiers:** INVERTED — candidates are opus/top (the pool quality is the
  ceiling); judges can be sonnet *with a written rubric*; synthesis top model.
- **Failure mode to guard:** homogeneous candidates. Vary the prompt/angle per
  candidate, not just the seed.

### 4. Adversarial generator–critic
Generator produces; critic (≥ generator's tier) attacks; loop until the
critic runs dry or a round limit hits.
- **Fits:** security review, claim verification, proofs, anything where
  plausible-but-wrong surviving is the disaster.
- **Tiers:** critic at or above generator; prompt critics to REFUTE with
  "default to refuted if uncertain", never to "review".

### 5. Iterative escalation ladder
One cheap agent attempts the whole task; on verified failure, re-dispatch the
same task one tier up with the failure evidence in the prompt. No fan-out.
- **Fits:** unknown-difficulty work — diagnosis, flaky bugs, "why is this
  slow". Paying top-tier upfront is premature when haiku might solve it.
- **Rule:** two failures at a tier → escalate. Never retry the same tier with
  the same spec.

### 6. Loop-until-dry accumulation
Repeated cheap probe rounds (optionally multi-modal: by-content, by-name,
by-time) until K consecutive rounds surface nothing new; verify survivors.
- **Fits:** unbounded discovery — bug hunts, edge-case enumeration, "find all
  the places that...". The risk is stopping early, not per-item error.
- **Tiers:** probes sonnet; the dedup is plain code (dedup vs everything SEEN,
  not everything CONFIRMED, or rejected findings recycle forever).

### 7. Null topology
One agent, or inline work. The correct choice whenever the task fits one
context window and has no independent parallel parts. Orchestration overhead
(spec-writing, result-merging, cache misses) is real; don't pay it for
single-file work.

## Choosing

1. Does it fit in one context with no parallelism win? → **7 (null)**.
2. Is difficulty unknown and the task singular? → **5 (ladder)**.
3. Is the deliverable a *design/choice* in a wide solution space? → **3 (panel)**.
4. Is the deliverable an *implementation* of a decided design? → **2 (contractor)**.
5. Is the deliverable *facts about a large surface* (index, audit, research)?
   → **1 (pyramid)**, with **6 (loop-until-dry)** replacing the fan-out when
   the surface size is unknown, and **4 (adversarial)** as the verify stage
   when wrong-but-plausible is the main risk.
6. Compose freely: contractor specs can be produced by a panel; a pyramid's
   verify stage can be adversarial; a ladder can sit inside any stage.

Always declare per-stage `model`/`effort` in `meta.phases` so the cost shape
is visible before the run starts. Escalate a failing stage via
`resumeFromRunId` (clean stages replay from cache), not the whole workflow.
