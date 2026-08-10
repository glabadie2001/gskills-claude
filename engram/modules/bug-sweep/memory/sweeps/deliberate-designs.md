# Deliberate designs — the standing not-bugs ledger

> **STATUS: EMPTY — no entries yet.** The first round close (or the first
> refuted/deferred finding) replaces this notice with entries below.

The canonical home of everything a reviewer must NOT report as a bug:
accepted trade-offs, refuted findings, deferred-by-decision items, and
known-pending manual checks. Round-prompt assembly includes this file
verbatim as the prompt's "Deliberate designs — do not report as bugs"
section — it exists so that knowledge lives HERE once instead of being
copied forward from prompt to prompt (which grows every prompt and every
archived copy monotonically).

## Conventions

- **Every entry cites its provenance**: the round that established it
  (`R<N>#<f>` for a refuted/deferred finding, or the round whose close
  accepted the trade-off) — that ref resolves through
  [INDEX](INDEX.md) to the findings artifact.
- **Entry shape**: one bullet — what the design is, the one-line WHY it is
  correct/accepted, and the provenance ref. Deferred items add
  `deferred by decision — fix tracked in <task ledger>`; pending manual
  checks add `pending, not a finding`.
- **Prune on change, never on age.** This file is assembled into EVERY
  round prompt: an entry whose underlying design has since changed
  actively suppresses real findings. When code invalidates an entry,
  delete it in the same change (journal the removal); entries are never
  removed merely for being old.
- **Keep entries one to three lines.** Mechanism prose belongs in the
  taxonomy ([bug-classes](../bug-classes.md)) or the journal; this ledger
  states the verdict, not the story.

## Accepted trade-offs

*(empty)*

## Refuted findings — and why they don't hold

*(empty)*

## Deferred by decision — do not re-report

*(empty)*

## Pending manual checks — not findings

*(empty)*
