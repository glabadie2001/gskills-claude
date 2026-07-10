# Incident postmortem

Run after a production incident or a verified escaped defect (survived
review AND tests). The analysis is the cheap part; the method IS the three
mandatory outputs. A postmortem that produces only narrative changed
nothing about the next incident.

Blameless by construction: the unit of analysis is the missing *mechanism*,
never the person. "X made a mistake" is not a cause; "nothing made that
mistake impossible or loud" is.

## Procedure

| Step | Output |
|---|---|
| Timeline | what happened, in order, with evidence (logs, commits, audit rows) — facts only, no analysis yet |
| Proximate cause | the direct trigger ("the poller sent the batch twice") |
| Root cause | why the system ALLOWED it ("send is decoupled from the dedup check and non-idempotent") — keep asking "why was that possible" past the first answer |
| Missing invariant | one sentence: "had X been enforced, this incident is impossible." This sentence drives all three outputs |
| Contributing factors | what widened the blast radius or delayed detection (no alert, silent catch, missing audit row) |

The proximate/root distinction is where most postmortems stop short: fixing
the trigger leaves the door open for the next trigger. The missing invariant
is the door.

## Mandatory outputs

1. **A regression test** that fails on the pre-fix code and encodes the
   missing invariant — not merely "the bug is fixed" but "this class of
   state cannot recur". Verify it actually fails on the old code (revert
   locally or assert against the old behavior) before trusting it.
2. **A durable guardrail**, picked by failure class:
   - recurring code pattern → a ratchet counter (`ratchet-refactor.md`)
   - planning blind spot → a new/sharpened premortem lens (`premortem.md`)
   - operating-knowledge gap → a memory/rule entry with the WHY
   - detection gap → an alert, audit row, or log line so the next
     occurrence is loud
   The test catches THIS bug; the guardrail catches its class, upstream.
3. **A sibling sweep** — the same defect pattern usually exists elsewhere
   (copy-paste, shared idiom, same author habit). Search for it now:
   grep/inline when the pattern is mechanical,
   `../../orchestration/references/loop-until-dry.md` when the surface is
   unknown. Report the sweep's coverage honestly — a capped or single-angle
   sweep must not read as exhaustive.

## Failure modes

- **Fix-without-test** — the incident recurs after the next refactor; the
  fix was a patch, not an invariant.
- **Test that never failed** — a regression test not verified against the
  old code often asserts the fix's implementation, not the invariant.
- **Stopping at proximate cause** — the trigger is fixed, the door stays
  open, the next trigger walks through it.
- **Narrative-only postmortem** — a well-written document with zero
  enforceable outputs. If nothing gained a test, gate, lens, or alert, the
  postmortem didn't happen.
- **Skipping the sibling sweep** — the same bug ships again from a file
  nobody reopened.
- **Blame framing** — "be more careful" is not a guardrail; anything whose
  enforcement depends on human vigilance will fail again the same way.
