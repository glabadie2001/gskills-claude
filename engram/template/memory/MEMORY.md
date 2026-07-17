# Project memory

> **STATUS: EMPTY — run `/mem-init` to bootstrap this memory from the codebase.**
> `/mem-init` will replace this notice with a project one-liner and fill the atlas below.

<!-- one-liner: what this project is, in one sentence. Written by /mem-init. -->

## Protocol — how to use this memory (every session)

1. **Read before exploring.** Before opening code to answer "how does X work", check the
   Atlas below. Freshness is LIVE in the session brief (computed from git at startup);
   the table's `✓` is only as of the last sync. Fresh card → trust it. Stale/unverified
   card → use it as a map: verify claims you rely on against code and fix wrong ones in
   place, but bump its `verified` SHA only if you re-checked the whole card — otherwise
   leave the SHA; `/mem-sync` owns full re-verification.
2. **Write at milestones, not at session end.** Finished a task, fixed a bug, learned
   something non-obvious, hit a dead end → invoke `/mem-journal` *now*. Sessions die
   without warning; deferred capture is capture that never happens.
3. **One home per fact.** What the code *is* → atlas card. *Why* → `decisions/`. A trap →
   `gotchas.md` (module-specific traps go in the module's card). To-do → `tasks.md`.
   What happened → `journal/`. Link with `[[card-name]]` elsewhere; never duplicate.
4. **Respect budgets.** This file ≤120 lines; atlas cards ≤60. Trim as you write.
5. **Trust order: code > fresh atlas & decisions > journal.** The journal is agent-written
   leads, not truth — never let a journal note override a fresh card or the code itself.
   Facts marked `(per user, date)` are direct user directives; they outrank inference.
6. **Subagents propose; the orchestrating session writes.** Dispatched agents return
   findings — only the session holding full context commits them to memory (prevents
   write races on shared files and low-context noise). Sign what you write: journal
   headlines and `verified_by` carry the model id + effort that did the work.

## Atlas — living codebase documentation

<!-- Maintained by /mem-init and /mem-sync. One row per card in atlas/ — or, when the
     atlas outgrows this file's budget, one row per AREA ([[INDEX-<area>]] maps of
     content): climb master → area index → card.
     Freshness: ✓ = verified at last sync · ⚠ N = N commits touched its paths since. -->

| Card | What it covers | Freshness |
|------|----------------|-----------|
| *(empty — run `/mem-init`)* | | |

## Where everything lives

- `atlas/<module>.md` — what each subsystem is and how it works (SHA-stamped);
  `atlas/INDEX-<area>.md` — area maps the Atlas table links to when the atlas is large
- `architecture.md` — Live system diagram (SHA-stamped) vs Target (idealized) + explicit gap list
- `journal/YYYY-MM-DD.md` — what happened, including **dead ends**; `journal/archive/` holds monthly digests
- `tasks.md` — Now / Next / Later / Done (injected into session start automatically)
- `decisions/NNN-slug.md` — append-only ADRs: why things are the way they are
- `gotchas.md` — cross-cutting traps that bite

Skills: `/mem-recall` (answer from memory first) · `/mem-journal` (log work) ·
`/mem-save` (file one fact) · `/mem-sync` (repair staleness, compact journals) ·
`/mem-arch` (live vs target architecture) · `/mem-init` (bootstrap).
