# Plan premortem

Run AFTER a plan is approved, BEFORE any code is written. Assume the plan
shipped and failed in production; work backward to the failure stories. One
pass, fixed lenses, every story dispositioned. The plan does not execute
while an undispositioned story exists.

## When to run

- Plans touching state mutation, mail/notifications, money, auth/tenancy,
  schema migrations, external side effects, or anything hard to reverse.
- SKIP for trivial reversible changes. The method's value depends on it
  staying cheap enough that it actually runs on the plans that matter.

## The lenses

Walk EVERY lens; "not applicable" is a finding (state why). Open-ended
"what could go wrong?" produces vibes — the lenses produce coverage.

1. **Idempotency / retries** — this step runs twice (retry, double-click,
   poller overlap, replayed request). What duplicates? What corrupts?
2. **Partial failure** — the plan has N steps and step k fails. What state
   is left behind? Can the operation resume, or does retry-from-scratch
   double-apply steps 1..k-1?
3. **Concurrency / races** — two tabs, two users, request + background job
   interleaved. Which shared state has no owner?
4. **Authz / tenancy** — wrong company, wrong user, stale session, a header
   the client controls. Who checked, and against what source of truth?
5. **Irreversibility** — which step, once run, cannot be undone (sent mail,
   deleted rows, external writes)? Is everything before it safe to abort?
6. **Wrong-assumption blast radius** — list the plan's unverified factual
   assumptions. For each: if false, is the failure loud (test/typecheck) or
   silent (wrong data in prod)? Silent ones need verification NOW, not
   during execution.

Grow this list from postmortems: any incident whose failure story no lens
would have surfaced adds a lens (or sharpens one). That feedback loop is
what makes the pair compound.

## Dispositions

Every failure story gets exactly one:

| Disposition | Meaning |
|---|---|
| **Change the plan** | the design enables the failure; redesign the step |
| **Add a guard** | idempotency key, transaction, lock, permission check — named in the plan, built with the feature |
| **Add a test** | the test is written IN this plan's scope, not "later" |
| **Accept, with reason** | explicitly waived; the reason and date go in the plan |

"Add a test later" is not a disposition. The premortem's output is a
"Premortem" section appended to the plan: stories, dispositions, accepted
risks. Execution starts only when the section is complete.

## Adversarial variant

For high-stakes plans, don't self-review — dispatch a critic with the plan
text and the lens list, framed to REFUTE ("find the failure story that ships;
default to 'this plan fails' if uncertain"), critic tier ≥ the tier that will
execute. See `../../orchestration/references/adversarial.md`. Self-premortem
by the plan's own author is the weakest form: sunk-cost attachment to the
design is exactly what the method exists to counter.

## Failure modes

- **Rubber-stamping** — a premortem that finds nothing on a state-mutating
  plan is a failed premortem, not a clean plan. Re-run with the adversarial
  variant.
- **Happy-path-only lenses** — checking that the plan works is a review;
  the premortem only asks how it fails.
- **Premortem after code is written** — sunk cost converts every finding
  into "accept". Run it strictly before execution.
- **Deferred dispositions** — "guard in a follow-up" means the failure
  window ships. Guards and tests land inside the plan's own scope.
- **Static lens list** — if incidents keep surfacing failure classes the
  lenses miss, the postmortem feedback loop is broken.
