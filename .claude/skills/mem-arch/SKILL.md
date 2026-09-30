---
name: mem-arch
description: Maintain the Engram architecture overview — a Live Mermaid diagram of what the codebase IS (SHA-verified against git) beside a Target diagram of what it SHOULD become, with an explicit gap list between them. Also renders an interactive X-ray report (computed layering, knots, hubs, DSM), extracts the real import graph, and diffs the architecture across branches.
argument-hint: [update | target | gaps | render | extract | flow | compare <base>..<head>]
when_to_use: Run `update` when the session brief or linter flags the architecture overview stale, or after structural work (new module, moved boundary, new external dependency). Run `target` to set or revise the idealized architecture. Run `render` to see the architecture as a diagnostic report, `extract` to check the diagram against the code's actual import graph, `compare` to see a refactor's architectural effect between two revs. Run with no argument for a freshness/gap status readout, or `gaps` to recompute the gap list.
---

# /mem-arch — live vs target architecture

File: `.claude/memory/architecture.md`. Mode: $ARGUMENTS (no argument → **status**).

## 0. Guards

- **Step 0 — resolve `<ROOT>`.** `.claude/memory/MEMORY.md` exists here → `<ROOT>` = `.`. Else if `.claude/engram-root` exists → `<ROOT>` = the relative path on its first line. Else if `*/.claude/memory/MEMORY.md` matches exactly one directory one level down → `<ROOT>` = that directory; several matches → pick the one the current work concerns and say so. No match → stop: "Engram not installed." Contains `STATUS: EMPTY` → stop: "Run /mem-init first." Every path below means `<ROOT>/.claude/memory/...`, and every `git` command runs as `git -C <ROOT> ...`.
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

1. Run the bundled extractor (stdlib only, installs nothing) from the repo root:
   `python <skill-dir>/extract.py --memory <ROOT>/.claude/memory --out <tmp> [--src DIR ...]
   [--skip-card testing-tooling ...] [--alias @/=./]`. It builds the file-level import
   graph (Python `ast`; TS/JS specifier scan honoring the alias, type-only imports dropped),
   collapses it onto the atlas cards' `paths:` globs and writes `extracted.json` +
   `extracted.mmd`. Prefer it over ad-hoc grep; use dependency-cruiser/madge/pydeps only to
   cross-check counts.
2. Filing rules the collapse relies on (fix the ATLAS, not the tool, when they are wrong):
   **most specific glob wins**, so a kernel/infra card may claim single files out of
   another card's directory; `graph_exclude:` globs on a card drop composition roots and
   entrypoints (DI root, `main`, workers that resolve ports from the root) from the graph
   — they import everything by design and otherwise knot every module into one SCC.
   Cross-cutting code (request context, tenant registry, telemetry, permission gate, URL
   builders) belongs in its own card, never in the feature that happens to own the file.
3. Read the report in this order: **file-level cycles** (the only true spaghetti signal —
   zero means no circular import exists), then **knots** (module SCCs the X-ray will draw
   as one row), then **two-way pairs**: for each, the WEAK direction is listed file by file.
   Those back-edges are what close the cycle, and each one is either a misfiled
   cross-cutting file (fix the card), a composition root (add `graph_exclude`), or real
   coupling (raise it; offer a gap/task). Never silently rewrite Live from the extraction.
3b. **Folder view (`--by-folder`, no atlas):** modules = directories
   (`--folder-depth 2`, `--split api/adapters`, `--group "app=app (routes)"`,
   `--exclude-file` for composition roots). Run it beside the card view whenever
   the card graph looks worse without a code change: the card view measures the
   ATLAS as much as the code, the folder view measures only the code. A knot in
   the card view that is absent in the folder view is a filing error.
4. Diff against Live: **divergent** (in code, not drawn) and **absent** (drawn, not in code);
   report both. Then offer `render` with a diff section (`before` = Live, `source` =
   `extracted.mmd`) so the divergence is visible, not just listed. External systems are not
   import-derivable: carry Live's external edges into the extracted graph verbatim.

## Mode: flow — the folder-first X-ray (code only, base vs HEAD)

The default picture for "what did this branch do to the architecture". It needs no atlas, so it
is also the view for repos without Engram cards. Folder graph first, cards last: the card graph
measures atlas filing as much as code.

1. Run the bundled builder from the repo root (stdlib only):
   `python <skill-dir>/build_xray.py --base master --src DIR [--src DIR ...] --out xray.html [-- <folder flags>]`.
   Always pass `--src` (else `.venv`/`node_modules` add phantom cycles). Folder flags after `--`
   go to `extract.py --by-folder` for BOTH graphs: `--split api/adapters`, `--group app=app/routes`,
   `--prefix features=app` (label a stack), `--exclude-file api/index.py` (composition root).
   Flags must match on both sides or every node diffs as added or removed.
2. It extracts HEAD and a temporary worktree of `--base`, then fills `xray.html` with three
   sections: folder diff (base to HEAD), folder graph at HEAD, atlas-card graph at HEAD (skipped
   when `.claude/memory/atlas` is absent, or with `--no-cards`). It prints knots and two-way pairs
   per graph and removes the worktree.
3. Read the result in this order: file-level cycles, knots, two-way pairs (the weak direction names
   the back-edge files). A knot in the card graph but not the folder graph is a filing error: fix
   the card globs (most specific glob wins; `entities/*/index.ts` also matches `entities/*/ui/index.ts`).
4. Send the file rendered inline, or publish it as an Artifact (republish the same path to keep the URL).

## Mode: compare <base>..<head> — architectural effect of a branch

For big refactors: what did the branch do to the shape?

1. For each rev: prefer its committed diagram (`git -C <ROOT> show <rev>:.claude/memory/architecture.md`,
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
