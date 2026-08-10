---
module: engram-mem-skills
paths:
  - engram/template/skills/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
The six memory skills — the Claude-invoked commands that bootstrap, query, and repair a
target repo's `.claude/memory/`: the workflow layer over the raw memory format.

## Key files
- `engram/template/skills/mem-init/SKILL.md` — one-time bootstrap: survey, fan out Explore agents, write atlas + architecture, fill MEMORY.md (`STATUS: EMPTY` guard)
- `engram/template/skills/mem-recall/SKILL.md` — read path: index → cards → journal, freshness check, backfill misses, log a recall event to `metrics/events.jsonl`
- `engram/template/skills/mem-journal/SKILL.md` — append-only daily entries; reconciles tasks/atlas/gotchas in the same turn
- `engram/template/skills/mem-save/SKILL.md` — single-fact router to exactly one home
- `engram/template/skills/mem-sync/SKILL.md` — repair pass: MIGRATIONS walk, staleness sweep, dead-reference lint, journal compaction + link retarget, task pruning, TOC rebuild, metrics scorecard
- `engram/template/skills/mem-sync/MIGRATIONS.md` — forward-only version walk v1→v7; check-first/idempotent; never rewrites append-only layers
- `engram/template/skills/mem-arch/SKILL.md` — architecture.md Live vs Target; modes update/target/gaps/render/extract/compare
- `engram/template/skills/mem-arch/xray.html` — standalone X-ray report; `render` injects a JSON payload at the `__ENGRAM_INPUT__` marker; layering/knots/hubs/DSM computed client-side

## How it works
Everything keys off frontmatter staleness: `verified` sha + `paths` globs;
`git log <verified>..HEAD -- <paths>` empty = fresh, else the card is a map, not truth.
mem-init creates the baseline, mem-recall consumes read-mostly (writing back on miss),
mem-save files single facts, mem-journal narrates + reconciles, mem-sync alone repairs bulk
staleness/compaction/migrations. All share the signature discipline (`verified_by` / journal
headline = exact model id, never guessed) and "subagents propose, the session writes."
The MIGRATIONS walk runs one hop at a time, check-first, before any other sync step.

## Invariants & gotchas
- MIGRATIONS.md's "Current tooling version" line is what mem-sync step 0 reads — bumping
  the version without a matching `## vN → vN+1` section (or vice versa) breaks the walk.
- `verified` bumps only on a WHOLE re-check — never on a partial patch. Stated identically
  in mem-sync, mem-save, mem-journal, mem-arch: duplicated by design.
- mem-arch's Target diagram changes only via explicit `/mem-arch target`; `update` must
  never touch it.
- xray.html's single injection point is the literal `__ENGRAM_INPUT__` marker; any other
  edit during render silently breaks the contract.
- `mem-sync/.impeccable/hook.cache.json` is a runtime cache artifact, not shipped content.

## Interfaces
**Depends on:** [[engram-memory-format]]
**Used by:** [[engram-installer]], [[bug-sweep-module]], [[engram-viewer]]
