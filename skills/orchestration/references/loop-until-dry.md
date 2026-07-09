# Loop-until-dry accumulation

Unbounded discovery — "find ALL the X" when the size of X is unknown: bug
hunts, edge-case enumeration, call-site sweeps where a fixed-N fan-out would
silently miss the tail. Keep probing until K consecutive rounds surface
nothing new.

## Stage design

| Stage | Width | Tier / effort | Notes |
|---|---|---|---|
| Probe rounds | 2–5 finders per round | sonnet, `effort:'low'`–medium | each round varies the search modality |
| Dedup | plain code | free | key on stable identity (file+line+kind), dedup vs everything SEEN |
| Verify survivors | per fresh finding | see adversarial.md | runs inside the loop, per round |
| Dry check | plain code | free | K=2 consecutive empty rounds ends the loop |

## Rules

1. **Dedup against everything SEEN, not everything CONFIRMED.** If verifier-
   rejected findings aren't in the dedup set, every later round rediscovers
   and re-verifies them — the loop never converges. This is the classic bug.
2. **Vary the modality per round, not just the seed.** Round 1 by-directory,
   round 2 by-symbol-name, round 3 by-content-pattern, round 4 by-history
   (recently changed files). Re-running the same search finds the same
   things; dryness is only meaningful across *different* angles.
3. **Feed the seen-list into later probes** — "these are already found; find
   what is NOT in this list." Saves tokens and forces novelty.
4. **K = 2 dry rounds** is the default stop; K = 1 stops on one unlucky
   angle. Also set a hard round cap (5–8) and `log()` when the cap, not
   dryness, ended the loop — a capped sweep must not read as exhaustive.
5. **Budget-aware variant**: gate the loop on `budget.remaining()` when the
   user gave a token target — but always guard `budget.total`, otherwise
   remaining() is Infinity and the cap is your only brake.
6. Stable identity keys are design work: too coarse (file only) merges
   distinct findings; too fine (message text) never dedups. file + line-bucket
   + category is usually right.

## Skeleton

```js
const seen = new Set(); const confirmed = []
let dry = 0, round = 0
while (dry < 2 && round++ < 6) {
  const found = (await parallel(MODALITIES[round % MODALITIES.length].map(m =>
    () => agent(`${m.prompt}\nAlready found (skip): ${[...seen].join(', ')}`,
      {model:'sonnet', effort:'low', schema: FINDINGS, phase:'Probe'})
  ))).filter(Boolean).flatMap(r => r.findings)
  const fresh = found.filter(f => !seen.has(key(f)))
  if (fresh.length === 0) { dry++; continue }
  dry = 0
  fresh.forEach(f => seen.add(key(f)))         // SEEN, not confirmed
  confirmed.push(...await verify(fresh))        // adversarial.md pattern
  log(`round ${round}: ${fresh.length} fresh, ${confirmed.length} confirmed`)
}
if (round >= 6) log('stopped by round cap, NOT dryness — coverage incomplete')
return confirmed
```

## Failure modes

- **Dedup-vs-confirmed** (rule 1) — non-convergence, re-verification churn.
- **Single-modality dryness** — one search angle runs dry while others were
  never tried; the loop reports exhaustive coverage it doesn't have.
- **Unstable keys** — findings phrased differently each round defeat dedup;
  key on locations and categories, never on prose.
- **No round cap** — a pathological generator (or too-fine keys) loops to the
  1000-agent backstop.
