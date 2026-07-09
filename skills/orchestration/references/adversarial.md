# Adversarial generator–critic

Claims that must not survive if wrong: security findings, bug reports,
proofs, "this refactor is safe". A generator produces; critics attack; only
what survives refutation ships. Usable standalone or as the verify stage of
a pyramid.

## Stage design

| Stage | Width | Tier / effort | Notes |
|---|---|---|---|
| Generate | 1–N | sonnet/opus per difficulty | findings or claims, schema-forced with evidence locations |
| Refute | 3 per claim (vote), or 3 lenses per claim | critic tier ≥ generator tier; opus `effort:'high'` for high stakes | kill on majority refutation |
| (Optional) Repair | 1 per killed-but-close claim | generator tier | fix and resubmit once |

## Rules

1. **Critics are prompted to REFUTE, never to "review".**
   Canonical prompt: "Try to refute this claim: <claim + evidence>. Attempt
   concrete counterexamples. Default to refuted=true if uncertain." A
   reviewer's incentive is agreement; a refuter's is a kill.
2. **Choose vote-redundancy vs lens-diversity deliberately:**
   - *Redundant vote* (3 identical refuters, majority rules): right when the
     claim fails in ONE way (a line number is wrong or it isn't). Tolerates
     sonnet critics.
   - *Diverse lenses* (correctness / security / does-it-reproduce, one critic
     each): right when the claim can fail in SEVERAL ways. Diversity catches
     failure modes redundancy can't. Requires each lens in the prompt.
3. **Critics get evidence, not conclusions.** Pass the claim plus its
   file:line evidence; let the critic re-read source. A critic that only sees
   the generator's summary can't attack the weakest link.
4. **Asymmetric stakes → asymmetric defaults.** For security/compliance
   claims, uncertain = refuted (don't ship shaky findings). For "is this
   safe to delete" claims, uncertain = NOT refuted (don't delete on doubt).
   State the default explicitly per run.
5. **One repair round maximum.** Endless generate–refute loops converge
   slowly; a claim that can't survive two rounds isn't ready.

## Skeleton (as a verify stage)

```js
const survivors = []
for (const claim of claims) {
  const votes = (await parallel(['correctness','security','repro'].map(lens =>
    () => agent(`Lens: ${lens}. Try to refute: ${JSON.stringify(claim)}. ` +
      `Default refuted=true if uncertain.`,
      {model:'opus', effort:'high', schema: VERDICT})
  ))).filter(Boolean)
  if (votes.filter(v => !v.refuted).length >= 2) survivors.push(claim)
}
```
(Pipeline claims through refutation rather than looping when N is large.)

## Failure modes

- **Polite critics** — "this seems plausible" is not an attack. The
  default-to-refuted instruction is what forces engagement.
- **Critic weaker than generator** — a sonnet critic rubber-stamps an opus
  generator's subtle error. Tier the critic at or above.
- **Refuting the wording, not the substance** — critics that kill claims on
  phrasing technicalities. Require the counterexample to be concrete:
  inputs/state → observed contradiction.
- **Survivorship laundering** — reporting survivors without noting the vote.
  Carry `votes` into the final output so downstream sees 2-1 vs 3-0.
