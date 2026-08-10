---
module: bug-sweep-module
paths:
  - engram/modules/bug-sweep/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Engram's first opt-in module: an adversarial-review campaign ledger and bug-class taxonomy
so reviewer rounds and class sweeps stay traceable years later. Installed via `-Modules bug-sweep`.

## Key files
- `engram/modules/bug-sweep/MODULE.md` — what the module adds and drives; module contract
- `engram/modules/bug-sweep/memory/sweeps/INDEX.md` — sole-entry-point ledger: one row per round/sweep → brief+findings, verdicts, fix commits
- `engram/modules/bug-sweep/memory/bug-classes.md` — bug-class taxonomy + hunt heuristics, with a `Distilled through: round N` backlog marker
- `engram/modules/bug-sweep/memory/sweeps/deliberate-designs.md` — standing not-bugs ledger, assembled verbatim into every round prompt
- `engram/modules/bug-sweep/MEMORY-snippet.md` — bullets appended to targets' MEMORY.md

## How it works
Template files ship in STATUS: EMPTY state; each file's header explains what replaces the
notice on first use. The [[codex-review]] skill drives the module: it assembles the full
reviewer prompt at run time (brief + INDEX-derived ground-covered + deliberate-designs
verbatim + template), archives only the brief, and its round-close distill step rolls
confirmed findings into bug-classes.md, excises before/after snippets into `sweeps/examples/`,
files refuted/deferred verdicts into deliberate-designs.md, and compacts distilled rounds'
INDEX verdict cells to counts + class ids.

## Invariants & gotchas
- The staged prompt for an un-run round lives OUTSIDE the repo — a working-tree review must
  never read its own instructions (`sweeps/INDEX.md`).
- `artifacts/` is append-only frozen history; the linter skips dead-mdlink inside it but
  escalates dead links elsewhere under `sweeps/` to ERROR — an unfixed link breaks the
  campaign hierarchy. Journal-day links get retargeted to digest anchors at compaction.
- `bug-classes.md` is never split per-class (only by family past ~250 lines) — classes are
  consumed together, pasted whole into prompts.
- `deliberate-designs.md` entries are pruned on CHANGE, never on age — a stale entry
  actively suppresses real findings, since it's injected into every prompt verbatim.
- Module install is additive/idempotent: files copied only where missing, snippet bullets
  appended only if absent; never clobbers existing memory.
- `examples/` and `artifacts/cold/` are documented conventions; the template ships only
  `artifacts/.gitkeep` — they materialize in live installs.

## Interfaces
**Depends on:** [[engram-installer]], [[engram-memory-format]], [[codex-review]]
**Used by:** [[engram-lint-ci]], [[engram-viewer]]
