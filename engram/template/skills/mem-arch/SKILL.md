---
name: mem-arch
description: Maintain the Engram architecture overview — a Live Mermaid diagram of what the codebase IS (SHA-verified against git) beside a Target diagram of what it SHOULD become, with an explicit gap list between them. Also renders an interactive X-ray report (computed layering, knots, hubs, DSM), extracts the real import graph, and diffs the architecture across branches.
argument-hint: [update | target | gaps | render | extract | compare <base>..<head>]
when_to_use: Run `update` when the session brief or linter flags the architecture overview stale, or after structural work (new module, moved boundary, new external dependency). Run `target` to set or revise the idealized architecture. Run `render` to see the architecture as a diagnostic report, `extract` to check the diagram against the code's actual import graph, `compare` to see a refactor's architectural effect between two revs. Run with no argument for a freshness/gap status readout, or `gaps` to recompute the gap list.
---

# /mem-arch — live vs target architecture

File: `.claude/memory/architecture.md`. Mode: $ARGUMENTS (no argument → **status**).

## 0. Guards

- `.claude/memory/MEMORY.md` missing → stop: "Engram not installed." Contains `STATUS: EMPTY` → stop: "Run /mem-init first."
- `architecture.md` missing (memory predates v4 — /mem-sync's migration walk normally creates it) → create it from the skeleton at the bottom of this skill, then continue in `update` mode to draw the Live diagram.
- Capture once: `git rev-parse --short HEAD` → `<HEAD>`, and today's date. Not a git repo → staleness checks are moot; still maintain the diagrams, keep `verified: 0000000`.

## Diagram rules (both diagrams)

- Mermaid `graph TD` (or `LR` if it reads better), **module granularity**: nodes ≈ atlas cards, node IDs = card names so the diagram doubles as a visual index of the atlas (a name that trips the Mermaid parser → `id["name"]`). External systems get distinct shapes: `db[(postgres)]`, `q>queue]`.
- Edges are runtime/dependency relations ("calls", "reads", "emits"); label an edge only when its nature isn't obvious from the endpoints.
- Same node IDs in Live and Target wherever the concept coincides — the eyeball-diff between the two diagrams is the point.
- 5–15 nodes. More → you are drawing the directory tree, not the architecture; coarsen.

## Mode: status (no argument)

1. Parse frontmatter (`paths`, `verified`, `target_set`). Run `git log --oneline <verified>..HEAD -- <paths>` (skip if no baseline).
2. Report in ≤6 lines: Live fresh / N commits behind / no baseline · Target set (date) or unset · open gap count from `## Gaps`. Recommend the fitting mode. Edit nothing.

## Mode: update — bring Live up to date with the code

1. **What changed:** `verified` is a real commit (`git cat-file -t`) → `git log --oneline <verified>..HEAD -- <paths>` then `git diff <verified>..HEAD --stat -- <paths>`; invalid or `0000000` → treat the whole diagram as unverified.
2. **Re-derive:** fresh atlas cards' `## Interfaces` sections are the expected edge list — the graph is latent in the atlas. Reconcile the diagram against that, and against code for whatever the diff touched or the atlas doesn't cover (entry points, imports — read enough to be sure of every edge you assert). Never draw an edge you can't anchor to a file.
3. **Edit Live IN PLACE** (add/remove/rename nodes and edges). If the code contradicts the *atlas* too, the cards are stale — flag them for /mem-sync rather than silently absorbing the difference here.
4. Bump `verified: <HEAD>`, `verified_date: <today>`, `verified_by: <your exact model id (+ effort if known)>` — only after the WHOLE diagram was re-checked; a partial patch-up leaves the old SHA (same rule as atlas cards).
5. Refresh `## Gaps` (below). If the code moved AWAY from the Target, say so explicitly in the report — raising that signal is why this file exists.
6. Also update `paths:` if the module footprint moved (new top-level dir, deleted module) — dead globs silently kill staleness detection, and the linter flags them as errors.

## Mode: target — set or revise the idealized architecture

1. The Target is a **decision, not an observation** — it encodes intent. If the user gave direction (in $ARGUMENTS or conversation), draw that. If not, propose one — start from Live and dissolve its known warts (atlas `Invariants & gotchas` sections and `gotchas.md` usually name them) — and **confirm with the user before writing**.
2. Draw/edit the Target diagram (same grammar, shared node IDs). Below it, 2–5 one-line "why this shape" bullets.
3. Set `target_set: <today>`. A significant direction change (not a first draft or cosmetic edit) → record an ADR per /mem-save mechanics (`decisions/` is append-only) and link it under the Target section.
4. Refresh `## Gaps`.

## Mode: render — X-ray report (visual diagnostics)

The Engram viewer already renders these diagrams interactively in place; this mode produces the standalone, deeper report (DSM, findings, diffs) as a file.

1. Pull the Live Mermaid block (plus a second graph when invoked from `extract`/`compare`).
2. Copy `xray.html` (bundled next to this skill) to a temp path. Replace the single line
   `var INPUT = null; // __ENGRAM_INPUT__` with `var INPUT = <json>;` where `<json>` is
   `{"project": "<repo> — Live", "generated": "<today>", "sections": [{"title": "Live architecture", "source": "<diagram>"}]}`
   and `<diagram>` is the Mermaid text JSON-escaped. A diff section instead carries
   `"before"` (base graph), `"beforeLabel"`, `"afterLabel"` alongside `"source"` (head graph). No other edits.
3. Send the file to the user rendered inline. The page computes layering, knots (strongly
   connected components), hub scores (fan-in × fan-out), pass-through count, and a dependency
   structure matrix from the edges — nothing is hand-maintained. It parses the `graph TD/LR`
   subset used in this file: `a --> b`, `a -->|label| b`, chains, `id[label]`, `id[(store)]`, `id>external]`.

## Mode: extract — the graph the code actually has

The Live diagram is testimony; the import graph is forensics. Diffing them makes erosion visible.

1. Build the file-level dependency graph with the ecosystem's extractor when one is available
   (dependency-cruiser or madge for JS/TS, pydeps or grimp for Python, `go list -deps`, jdeps,
   cargo-modules); fallback: grep import/require/use statements. Read-only; install nothing without asking.
2. Collapse file edges onto the atlas cards' `paths:` globs — node IDs = card names, the same
   IDs as Live. Drop self-edges and edges into cardless vendored code; keep external systems
   only where Live names them.
3. Diff against Live: **divergent** (in code, not drawn) and **absent** (drawn, not in code).
   Report both — each one is either a stale diagram (fix via `update`) or real erosion (raise
   it; offer a gap/task). Never silently rewrite Live from the extraction.
4. Offer `render` with a diff section (`before` = Live, `source` = extracted) so the divergence
   is visible, not just listed.

## Mode: compare <base>..<head> — architectural effect of a branch

For big refactors: what did the branch do to the shape?

1. For each rev: prefer its committed diagram (`git show <rev>:.claude/memory/architecture.md`,
   Live block). If the rev predates Engram or its diagram was stale, run the `extract` recipe
   against a worktree of that rev instead — never against the working tree of the wrong branch.
2. `render` one diff section: `before` = base graph, `source` = head graph, labels = rev names.
   The report shows added/removed modules and edges on one canvas, both DSMs, and vital-sign
   deltas (tangle, cycle edges, depth, hub score).
3. Summarize the deltas in chat as well — the report is the evidence, not the summary.

## Gaps — regenerate whenever either diagram changes

Diff the diagrams structurally: nodes/edges only in Live (to dissolve), only in Target (to build), same node with different responsibilities (to reshape). One dated bullet each:

```
- **GAP (YYYY-MM-DD):** <what differs> — <why it matters> — tracked: <tasks.md item | [[adr-NNN]] | untracked>
```

Keep the original date while a gap persists; delete closed gaps (the journal keeps the story). Offer — never do silently — to seed untracked gaps into `tasks.md ## Later`. Target unset → the section is the single line `- *(target not set)*`.

## Budget & report

File ≤120 lines — trim prose before nodes. Finish with: nodes/edges changed, Live freshness now, gap count (closed/opened), anything flagged for /mem-sync.

## Skeleton (only for recreating a missing file)

````markdown
---
paths:
  - <union of atlas cards' globs>
verified: 0000000
verified_date: <today>
verified_by: <your model id>
target_set: (none)
---

# Architecture overview

Maintained by `/mem-arch`. **Live** = what the code IS, verified like an atlas card.
**Target** = what it SHOULD become, set by decision. **Gaps** = the difference, kept
explicit so drift is a choice, not an accident.

## Live — what the code is

```mermaid
graph TD
```

## Target — what it should become

> **Not set.** Run `/mem-arch target` to record the idealized architecture.

## Gaps — live vs target

- *(target not set)*
````
