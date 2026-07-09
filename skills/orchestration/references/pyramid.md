# Pyramid / map-reduce (bottom-up)

Facts about a large surface: cheap wide readers → verification → one synthesis.

## Stage design

| Stage | Width | Tier / effort | Produces |
|---|---|---|---|
| Fan-out | one agent per dimension/area | haiku or sonnet, `effort:'low'` | structured facts (schema-forced) |
| Verify | per finding, or per dimension | opus `effort:'high'`, OR 3+ sonnet majority vote | verdicts: confirmed / reclassified / not-found |
| Synthesize | exactly 1 | top model, `effort:'high'` | the deliverable |

Decompose the fan-out by *how the surface is organized* (per subsystem, per store,
per file-cluster), not by finding type — readers should own disjoint territory so
misses are attributable. Add one extra fan-out agent for the seams between
territories (consumers, cross-references) — that agent usually finds what the
territorial ones can't.

## Rules

1. **Schema-force every fan-out agent** — the `schema` option, with file/line
   required fields. Facts without locations can't be verified.
2. **Verifiers get the full inventory**, not just their slice — hunting for
   *missed* items requires knowing what was claimed. This is a legitimate
   barrier (`parallel` then verify), one of the few.
3. **Verifiers re-read source at claimed locations.** Prompt: "confirm by
   reading the actual code at file:line; reclassify with reason if wrong."
   Include one purely adversarial verifier whose job is attacking the framing,
   not the line numbers (see adversarial.md).
4. **The synthesizer may overrule** — give it explicit authority and tools to
   re-read disputed sources, and a conflict rule ("validators beat
   investigators; when validators disagree, read the code and rule").
5. Pipeline the verify stage per-dimension when no cross-dimension dedup is
   needed; barrier only for dedup/gap-hunting.

## Skeleton

```js
export const meta = { name: '...', description: '...', phases: [
  { title: 'Investigate', model: 'sonnet' },
  { title: 'Verify', model: 'opus' },
  { title: 'Synthesize', model: 'fable' },
]}
phase('Investigate')
const found = (await parallel(AREAS.map(a => () =>
  agent(a.prompt, {phase:'Investigate', model:'sonnet', effort:'low', schema: FACTS})
))).filter(Boolean)
phase('Verify')  // barrier: verifiers need the full inventory to hunt gaps
const inv = JSON.stringify(found)
const verdicts = (await parallel(VERIFIERS.map(v => () =>
  agent(v.prompt + inv, {phase:'Verify', model:'opus', effort:'high', schema: VERDICTS})
))).filter(Boolean)
phase('Synthesize')
return agent(SYNTH_PROMPT + inv + JSON.stringify(verdicts),
  {phase:'Synthesize', effort:'high'})  // omit model → inherits session (top)
```

## Failure modes

- **Rubber-stamp verification** — verifiers prompted to "review" confirm
  everything. Prompt to refute; require a reason per verdict.
- **Territory gaps** — two readers each assume the other covered a boundary
  file. Assign territories as explicit file/dir lists; add the seams agent.
- **Synthesis from summaries only** — if validators conflict and the
  synthesizer can't read code, it averages instead of ruling. Give it tools.
- **Silent truncation** — if fan-out is capped (top-N files), `log()` what was
  dropped; a capped sweep that reads as exhaustive is worse than none.
