# Iterative escalation ladder

Unknown-difficulty singular tasks: one cheap agent attempts the WHOLE task;
escalate one tier per verified failure. No fan-out — the bet is that the task
is easier than it looks, and the ladder caps the loss if it isn't.

## Stage design

| Rung | Tier | When reached |
|---|---|---|
| 1 | haiku (mechanical-looking) or sonnet | first attempt |
| 2 | one tier up | after 2 failed verifications at rung 1 |
| 3 | opus / top model | after 2 failed verifications at rung 2 |
| 4 | inline (orchestrator) | the ladder itself failed — the task was under-specified, not under-powered |

## Rules

1. **Verification must be cheap and objective**, or the ladder can't run:
   a failing test to make pass, a repro to eliminate, a command whose output
   proves the fix. If success can't be checked mechanically, the ladder is
   the wrong topology (you'd escalate on vibes).
2. **Two failures per rung, not one.** The first failure buys information;
   feed the evidence (error output, what was tried) into the second attempt
   at the SAME tier. One-failure escalation overpays; three underpays.
3. **Escalate with the case file.** Each rung's prompt includes: the task,
   all prior attempts, why each failed (verbatim evidence, not summaries).
   The expensive model's advantage is judgment over the accumulated
   evidence — don't make it rediscover rung 1's dead ends.
4. **Never same-tier same-spec retries.** A retry must change tier, spec, or
   evidence. Identical retries are the polling-loop of dispatch.
5. **Recognize spec failure vs capability failure.** If two rungs fail the
   same way, the spec is ambiguous — stop climbing, fix the spec (or take it
   inline). If they fail differently, capability is the constraint — keep
   climbing.
6. Rung 1 tier heuristic: start at haiku only when the task *looks*
   mechanical and verification is airtight; otherwise start at sonnet.
   Starting too low costs one cheap round; starting too high forfeits the
   ladder's entire savings.
7. **A spike task needs its kill criterion IN the rung prompt, with "an
   honest negative is a success" stated explicitly.** A rung can succeed
   functionally and still rule against shipping (the task's own acceptance
   economics — "keep it only if clearer than the alternative"). That verdict
   is a ladder SUCCESS at the cheapest possible tier, not a failure to
   escalate — but only if the prompt says so; an agent that just built the
   thing will otherwise rationalize keeping it. Field evidence (Datalog lint
   spike, 2026-07): rung-1 sonnet built a working stratified evaluator AND
   honestly reported it lost its own fewer/clearer-lines bar; the pinned
   delete-without-ceremony clause is what made the cheap rung's verdict
   trustworthy, and no escalation was ever needed.

## Shape

Usually the Agent tool with sequential calls (the orchestrator holds the
case file between rungs), not a Workflow — but as a Workflow stage:

```js
let evidence = ''
for (const tier of ['sonnet', 'opus']) {
  for (let attempt = 0; attempt < 2; attempt++) {
    const r = await agent(TASK + evidence, {model: tier, schema: RESULT})
    const check = await agent(`Run ${VERIFY_CMD}; report pass/fail + output`,
      {model: 'haiku', schema: CHECK})
    if (check?.passed) return r
    evidence += `\n\nATTEMPT (${tier} #${attempt+1}) FAILED:\n${check?.output}`
  }
}
return {escalate: 'inline', evidence}
```

## Failure modes

- **Sunk-cost climbing** — spec failures escalated as capability failures;
  rung 3 fails exactly like rung 1, expensively. Apply rule 5.
- **Evidence-free escalation** — re-prompting the bigger model with the
  original task only. It repeats the cheap model's first dead end at 10× cost.
- **Subjective verification** — "does this look fixed?" lets a cheap rung
  self-certify. The checker must run the command, not read the diff.
