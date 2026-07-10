# Ratchet refactor

Multi-session refactor/migration driven by a countable violation metric. The
ratchet's promise: the count only ever goes down. Baseline it, gate increases,
sweep to zero in waves, then keep the gate as a permanent invariant.

## Stage design

| Stage | Who | Notes |
|---|---|---|
| Define the metric | orchestrator, inline | the hard part — see rules 1–3 |
| Build the counter | inline or haiku | a script in the repo, one number out, exit non-zero above ceiling |
| Baseline + gate | inline | current count = ceiling; wire into CI/pre-commit so every change runs it |
| Discovery (if needed) | loop-until-dry | when violations aren't grep-able and need semantic judgment to enumerate |
| Sweep waves | contractor per wave | each wave scoped by file ownership; lower the ceiling after each verified wave |
| Zero + keep gate | inline | ceiling=0 becomes a standing invariant, not a finished project |

## Rules

1. **The metric must be mechanically countable.** Grep pattern, AST rule,
   import check, route-table scan — something a script answers with a number.
   If a human must judge whether a line violates, the ratchet cannot gate CI
   and enforcement decays to good intentions.
2. **Tier violations when severities differ.** Separate counters (tier1 =
   must-fix, tier3 = accepted-for-now) let you declare victory on the tier
   that matters while the long tail burns down on its own schedule.
3. **Baselined exceptions are explicit, dated, and reasoned.** A violation
   accepted-by-decision goes in an allowlist entry with WHY and WHEN, and the
   counter excludes it — so zero is reachable and means something. An
   allowlist addition gets the same review scrutiny as the code it excuses.
4. **The ceiling is a hard gate, not a dashboard.** New code that raises the
   count fails the build. A ratchet that only reports is a metrics page;
   ratchets ratchet because increases are impossible, not discouraged.
5. **Lower the ceiling after every verified wave.** Sweep a wave, run the
   counter, commit the new (lower) ceiling in the same change. Otherwise the
   headroom you just created gets silently spent by the next feature.
6. **Sweep waves are contractor dispatches.** Each wave gets a precise spec
   (the violations in scope, the target idiom, the verification command) and
   disjoint file ownership. See `../../orchestration/references/contractor.md`.
7. **At zero, the gate stays.** Deleting the counter after victory is how the
   debt class returns. Zero converts the ratchet from a project into an
   invariant; the script keeps running in CI forever.

## Deciding what counts

- Key the counter on *semantics*, not location, where possible (an import of
  the forbidden module, a call to the deprecated symbol) — location-keyed
  counters are gamed by moving violations instead of removing them.
- Deferred-by-decision items are exceptions (rule 3), not metric redesigns.
  Redefining the metric mid-ratchet resets everyone's mental model of what
  the number means; prefer a second tier over a moving definition.

## Failure modes

- **Judgment-based metric** — unenforceable; the ratchet was never real.
- **Gate not in CI** — the count drifts up between sessions and each sweep
  starts by re-fixing regressions. The ratchet only ratchets if every change
  runs the counter.
- **Silent allowlist growth** — exceptions added without reason/date/review
  are just violations with better PR. Audit the allowlist each wave.
- **Ceiling never lowered** — waves complete but headroom absorbs new debt;
  net count stalls while everyone believes progress is happening.
- **Metric gaming** — violations moved, renamed, or wrapped rather than
  removed. Spot-check a sample of each wave's "fixed" items against intent.
- **Zero-then-delete** — the gate is removed at victory and the debt class
  quietly returns within months.
