# Judge panel / tournament

Design problems in wide solution spaces: N strong, deliberately diverse
attempts → rubric-scored judging → synthesis grafts runners-up onto the
winner. Beats one-attempt-iterated when a local optimum is the risk.

## Stage design — note the INVERTED cost shape

| Stage | Width | Tier / effort | Notes |
|---|---|---|---|
| Generate | 3–5 candidates | opus or top model, `effort:'high'` | the pool quality is the ceiling — never cheap out here |
| Judge | 2–3 judges | sonnet WITH a written rubric; opus if no rubric possible | gates FIRST (pass/fail), then scores; independent, not conferring |
| Synthesize | 1 | top model | winner + grafts from runners-up, with reasons; runs the forest check |

## Rules

1. **Diversity by construction, not by temperature.** Give each generator a
   different *angle*, stated in its prompt: MVP-first vs risk-first vs
   user-first; optimize-for-migration vs optimize-for-greenfield; the
   incumbent approach vs the challenger. Identical prompts produce
   near-identical candidates and the panel degenerates to redundancy.
2. **Write the rubric before generating — in two parts: gates, then
   scores.** Gates are pass/fail constraints derived from the user's stated
   pillars and the mission ("anything a game in the envelope needs must not
   require a core edit"); a gate failure cannot be outscored, however high
   the candidate totals elsewhere. Weighted criteria (e.g. correctness ×3,
   migration cost ×2, simplicity ×1) rank only the candidates that pass.
   Weighted scoring SMOOTHS OVER absolute violations by construction — if
   every requirement is a weight, a mission failure is just a deduction.
   Extract the gates by asking: what did the user say this is FOR, and what
   outcome would make them reject the winner outright?
3. **Judges apply gates first, score second, and never credit eloquent
   limitations.** Candidates must declare their limitations/"cannots" in the
   common schema, and judges test each declared limitation against the
   gates — a well-argued wall inside the mission scope is a gate FAILURE,
   not a point of honesty to reward. (Observed failure: a rubric asking
   "are the cannots defensible?" trained judges to score rationalization
   up.) Schema-force: `{candidate, gates: {gate: pass|fail, why}, scores:
   {...}, total, risks}`.
4. **Candidates must be commensurable.** Force a common output schema
   (problem restatement, approach, key tradeoffs, declared limitations,
   sketch of the riskiest part) so judges compare designs, not prose
   quality.
5. **Synthesis is not just picking the winner.** Prompt it to graft: "adopt
   the winner; steal anything from the runners-up that scored higher on any
   single criterion; list what you took and why."
6. **Synthesis runs the forest check.** Before adopting, re-read the
   winner's declared limitations against the user's stated purpose — not
   the rubric, the purpose. Rubric-satisfaction and mission-satisfaction
   diverge exactly where the rubric was written imperfectly, and the panel
   optimizes whatever frame it was given; the forest check is the one step
   that owns questioning the frame. A limitation that violates the purpose
   escalates to the user as a finding ("the best candidate still can't X —
   the frame may be wrong"), it does not ship inside a winning design.

## Skeleton

```js
phase('Generate')
const candidates = (await parallel(ANGLES.map(a => () =>
  agent(DESIGN_PROMPT + `\nAngle: ${a}`, {phase:'Generate', model:'opus',
    effort:'high', schema: CANDIDATE})
))).filter(Boolean)
phase('Judge')  // barrier: judges need all candidates
const scores = (await parallel(JUDGES.map((j,i) => () =>
  agent(`Rubric:\n${RUBRIC}\nScore each candidate independently.\n` +
    JSON.stringify(candidates), {phase:'Judge', model:'sonnet', schema: SCORES,
    label:`judge:${i}`})
))).filter(Boolean)
phase('Synthesize')
return agent(`Winner per summed scores; graft best ideas from runners-up.\n` +
  JSON.stringify({candidates, scores}), {phase:'Synthesize', effort:'high'})
```

## Failure modes

- **Homogeneous pool** — same-prompt candidates converge; the panel cost buys
  nothing. Angles in prompts, always.
- **Prose bias** — judges reward the best-written candidate. The common
  schema and per-criterion scoring counter this.
- **Rubric capture** — a rubric that encodes the answer ("must use events")
  makes the panel theater. Criteria describe *qualities*, not mechanisms.
- **Pillar-blind scoring (missing the forest)** — every requirement encoded
  as a weight, none as a gate: candidates that violate the mission's
  pillars survive on points, and their "honest limitations" sections read
  as rigor and score UP. The panel then unanimously crowns a design the
  user rejects on sight. Gates before scores (rule 2), limitations tested
  against gates (rule 3), forest check at synthesis (rule 6).
- **Skipping synthesis grafts** — the second-best candidate usually contains
  the best single idea. Picking the winner verbatim wastes the pool.
