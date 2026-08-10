---
module: engram-design-docs
paths:
  - engram/README.md
  - engram/DESIGN.md
  - engram/FIELD-NOTES.md
  - engram/CONCEPTS.md
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
The rationale corpus for the Engram engine: why it's built this way, evidence the bets are
sound, and ideas held for later. Read before changing engine mechanics, not just templates.

## Key files
- `engram/README.md` — quickstart, install flow, feature table, day-to-day narrative (onboarding-facing)
- `engram/DESIGN.md` — canonical rationale: five death modes, layer/volatility model, protocol, self-measurement design
- `engram/FIELD-NOTES.md` — three-angle field survey (products/research/practitioners) that validated or adjusted the design
- `engram/CONCEPTS.md` — ideas that survived design discussion but aren't built; a holding pen, not a backlog

## How it works
DESIGN.md is the source of truth: every mechanism is framed as countering one of five named
death modes (write-nothing, stale-confident, bloat, write-only, fragmentation). README
restates the death-mode table for onboarding — a deliberate duplication, not a single-home
violation to "fix." FIELD-NOTES is evidence, not narrative: DESIGN's "Field validation"
section cites it, and each of its eight adopted deltas traces to a specific mechanism.
CONCEPTS is pre-DESIGN staging: an entry lives there until built (then moves into DESIGN)
or rejected (then stays with the rejection noted) — a rejected idea is never silently
re-proposed.

## Invariants & gotchas
- The five-death-modes table is the axiom: a new engine mechanism should be traceable to
  one of the five, and README's copy must stay consistent with DESIGN's when either changes.
- A CONCEPTS entry describing something now built is a documentation bug — move it into
  DESIGN.md, don't leave it duplicated.
- FIELD-NOTES' "Considered and rejected" and "Open questions" sections are load-bearing:
  they prevent re-litigating vector-DB/decay-curve options already surveyed and declined.
- Current CONCEPTS entry (hub-and-spoke multi-user reconciliation, 2026-08-10) is unbuilt
  intent only — no code implements team sync; don't assume it exists when reasoning about
  the installer or /mem-sync.

## Interfaces
**Depends on:** none — this is the rationale layer other modules point back to
**Used by:** [[engram-installer]], [[engram-memory-format]], [[engram-mem-skills]], [[engram-hooks]], [[engram-lint-ci]], [[engram-viewer]], [[bug-sweep-module]]
