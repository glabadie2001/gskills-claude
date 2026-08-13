---
module: engram-memory-format
paths:
  - engram/template/memory/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Defines the project-memory template: the always-loaded MEMORY.md protocol plus atlas,
journal, decision, gotcha, task, and metrics formats copied into targets' `.claude/memory/`.

## Key files
- `engram/template/memory/MEMORY.md` — protocol + Atlas index; copied as-is into new installs, then edited in place by mem-* skills
- `engram/template/memory/architecture.md` — Live vs Target Mermaid diagrams + Gaps, frontmatter-driven staleness (`paths`, `verified` SHA)
- `engram/template/memory/atlas/_template.md` / `atlas/_index.md` — per-module card contract and area-index (`INDEX-<area>.md`) format
- `engram/template/memory/decisions/_template.md` — append-only ADR format (NNN-slug.md)
- `engram/template/memory/journal/_template.md` — daily append-only journal entry shape, signed with model+effort
- `engram/template/memory/gotchas.md`, `tasks.md` — cross-cutting traps; Now/Next/Later/Done ledger
- `engram/template/memory/metrics/scorecard.md` — generated placeholder, filled by /mem-sync from `metrics/events.jsonl`
- `engram/template/memory/VERSION` — memory format version stamp (currently 9)
- `engram/template/memory/.gitattributes` — manifest sidecar attrs: `-text -diff merge=binary` (regenerate on conflict, never merge)

## How it works
One home per fact: atlas card = what code IS, decisions/ = why, gotchas.md = traps,
tasks.md = to-dos, journal/ = what happened. Atlas cards carry frontmatter (`paths`,
`verified` SHA — `0000000` = ASSUMED at birth, `verified_by`) plus a script-generated
`<module>.manifest` sidecar (blob sha + path at the verified commit); freshness =
set-compare vs HEAD (see [[adr-001|decisions/001]]), refined by the
`git log <verified>..HEAD -- <paths>` range check that architecture.md still uses alone. Templates are placeholders only — /mem-init
bootstraps real content, /mem-sync re-verifies and compacts, /mem-journal and /mem-save
append. Everything here is copied byte-for-byte on install and never overwritten on
re-install.

## Invariants & gotchas
- `architecture.md` frontmatter `paths` must never be a bare `**` — it would include
  `.claude/memory/` itself and make the Live diagram perpetually stale (`architecture.md:14`)
- Atlas card `paths` globs must avoid brace expansion (`{a,b}`) — git-pathspec doesn't
  support it and staleness detection silently breaks (`atlas/_template.md:16`)
- decisions/ and journal/ are append-only; never edit history, only supersede/append
- Budgets are convention here (MEMORY.md ≤120 lines, cards ≤60) — [[engram-lint-ci]] is
  what actually flags over-budget files and version drift
- Install is idempotent — template edits only affect FRESH installs; existing memories
  pick up format changes via /mem-sync's MIGRATIONS.md walk, never via the installer

## Interfaces
**Depends on:** none (static template)
**Used by:** [[engram-installer]], [[engram-mem-skills]], [[engram-lint-ci]]
