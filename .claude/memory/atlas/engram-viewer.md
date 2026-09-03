---
module: engram-viewer
paths:
  - engram/viewer/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Zero-dependency single-file browser app for watching an Engram memory live: polls
`.claude/memory/`, renders layers as pages, shows real-time diffs and a wikilink graph.

## Key files
- `engram/viewer/engram-viewer.html` — the entire app: HTML shell, CSS, one script block; no build step, no imports

## How it works
Connect uses `showDirectoryPicker` (File System Access API) with the handle persisted in
IndexedDB for one-click reconnect. `poll()` walks the tree every 1500ms, diffs mtime/size
against the last-seen map, re-reads changed files, computes an LCS line diff, re-renders.
A hand-rolled markdown renderer handles headings/lists/tables/frontmatter/wikilinks — no
library. Two custom visualizations: in-place mermaid blocks (small `graph TD/LR` subset
parser, Tarjan SCC for cycles/hubs, SVG layered layout) and a whole-memory wikilink graph
(force-directed canvas). The graph is deliberately low-motion: node positions persist to
`localStorage.eng_layout_<rootName>`, a cold graph simulates ~240 ticks off-screen and
fits to view before the first paint, and rebuilds reheat only in proportion to what
changed (same node+link set → no motion at all). An Obsidian-style ⚙ panel exposes the
force constants (center/repel/link/link-distance), display scales (node size, link
thickness, text-fade threshold) and an orphan filter, persisted to
`localStorage.eng_graph_cfg`.

## Invariants & gotchas
- Chromium-only (File System Access API); no polyfill — warns and suggests
  `python -m http.server` when the picker fails on `file://`.
- First poll seeds the content cache silently WITHOUT emitting diff events — connecting
  never shows "everything added".
- Walk caps at depth 4, skips files ≥1MB, tracks only `*.md` plus `sweeps/*.{txt,js,json}`
  — anything else is invisible to the viewer.
- `_`-prefixed basenames (format templates) are filtered from sidebar, backlinks, and graph.
- The mermaid renderer understands only the subset /mem-arch's contract emits
  (`a --> b`, `a -->|label| b`, few node shapes); anything else falls back to a plain pre block.
- Stale-card detection only scans MEMORY.md and `INDEX-*.md` tables for `⚠` rows — a
  convention tied to how indexes are written, not a generic check.
- Wikilink resolution: exact atlas path → `adr-N` → `decisions/NNN-*` → first basename match
  anywhere — ambiguous if two files share a basename outside atlas/decisions.
- Diffs are session-local (since connect); earlier history is git's job.
- The saved graph layout is keyed by `rootName` — the *picked folder's* name, not a path.
  Two repos with the same basename share one layout blob (harmless: unknown paths are
  ignored, and the saved map is merged rather than replaced on write).
- `buildGraph()` is the only place allowed to raise `gAlpha` on a rebuild; adding a
  `gDirty = true` next to a view toggle re-introduces the jump-on-open bug.

## Interfaces
**Depends on:** [[engram-memory-format]], [[engram-mem-skills]]
**Used by:** none — standalone leaf tool, pointed to from the README
