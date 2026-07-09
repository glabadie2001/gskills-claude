# Judge panel / tournament

Design problems in wide solution spaces: N strong, deliberately diverse
attempts → rubric-scored judging → synthesis grafts runners-up onto the
winner. Beats one-attempt-iterated when a local optimum is the risk.

## Stage design — note the INVERTED cost shape

| Stage | Width | Tier / effort | Notes |
|---|---|---|---|
| Generate | 3–5 candidates | opus or top model, `effort:'high'` | the pool quality is the ceiling — never cheap out here |
| Judge | 2–3 judges | sonnet WITH a written rubric; opus if no rubric possible | judges score all candidates; independent, not conferring |
| Synthesize | 1 | top model | winner + grafts from runners-up, with reasons |

## Rules

1. **Diversity by construction, not by temperature.** Give each generator a
   different *angle*, stated in its prompt: MVP-first vs risk-first vs
   user-first; optimize-for-migration vs optimize-for-greenfield; the
   incumbent approach vs the challenger. Identical prompts produce
   near-identical candidates and the panel degenerates to redundancy.
2. **Write the rubric before generating.** Criteria + weights (e.g.
   correctness under the known constraints ×3, migration cost ×2, blast
   radius ×2, simplicity ×1). A rubric is what lets mid-tier judges work; it
   also forces you to state what "good" means, which sometimes settles the
   question without a panel.
3. **Judges score independently and in isolation** — each judge scores every
   candidate against the rubric with a one-paragraph justification per score.
   Schema-force: `{candidate, scores: {...}, total, risks}`.
4. **Candidates must be commensurable.** Force a common output schema
   (problem restatement, approach, key tradeoffs, sketch of the riskiest
   part) so judges compare designs, not prose quality.
5. **Synthesis is not just picking the winner.** Prompt it to graft: "adopt
   the winner; steal anything from the runners-up that scored higher on any
   single criterion; list what you took and why."

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
- **Skipping synthesis grafts** — the second-best candidate usually contains
  the best single idea. Picking the winner verbatim wastes the pool.
