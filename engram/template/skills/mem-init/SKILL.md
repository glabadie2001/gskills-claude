---
name: mem-init
description: Bootstrap Engram memory for this codebase — survey the repo, partition into modules, fan out exploration agents, write atlas cards, and fill MEMORY.md so memory starts full, not empty.
when_to_use: Once per repo, right after installing Engram, while MEMORY.md still shows "STATUS: EMPTY". Never on an already-initialized repo — use /mem-sync for that.
---

# mem-init — bootstrap Engram memory

All paths relative to repo root. Memory lives in `.claude/memory/`.

## 0. Guards

1. `.claude/memory/MEMORY.md` must exist. Missing → stop: "Engram not installed — run the installer first."
2. Read MEMORY.md. If it does NOT contain the `STATUS: EMPTY` marker → already initialized. Stop and point the user to `/mem-sync`.
3. Run `git rev-parse --short HEAD`.
   - Succeeds → capture the short sha ONCE. Every card written this run uses this same sha.
   - Fails but `git rev-parse --git-dir` succeeds → a git repo with NO commits yet: suggest
     committing first (cards verified against a real sha from day one); if the user declines,
     use `verified: 0000000` and note /mem-sync will re-baseline after the first commit.
   - Both fail (not a git repo) → warn: staleness tracking disabled; use `verified: 0000000`.

## 1. Survey the repo (inline — do NOT delegate this step)

Read yourself: repo root listing, README, manifest/config files (package.json, pyproject.toml, Cargo.toml, *.csproj, go.mod, …), top-level source dirs.

Produce the module partition:
- Aim for 5–15 cards, cut along ARCHITECTURAL seams. A module = something you'd explain as one unit ("auth", "api", "build-pipeline") — NOT a literal mirror of the directory tree.
- Tiny repos (<~20 source files): 2–4 cards is correct. Never pad the count.
- Big repos where a faithful partition needs >20 cards: keep the cards honest and ALSO
  group them into 3–8 areas — you'll write hierarchical indexes in step 4. Never merge
  unrelated modules just to fit the index budget.
- Each planned card gets: kebab-case name, one-line scope, candidate `paths` globs.
- VERIFY every glob actually matches files: `git ls-files '<glob>'` must produce NON-EMPTY OUTPUT (an empty result with exit 0 still means broken — check the output, not the exit code). Globs must be git-pathspec compatible: NO brace expansion (`src/{a,b}/**` matches nothing in git — use two entries). No inline `#` comments in frontmatter. A bad glob silently breaks staleness detection forever — fix or drop it now.

## 2. Fan out exploration

Dispatch one read-only `Explore` agent per planned card, in parallel batches. Pass `model: sonnet` explicitly; use `model: opus` only for an architecturally gnarly module (concurrency, metaprogramming, framework internals).

Each agent's prompt MUST include the module name + scope, its `paths` globs, and this verbatim:

```
Read the actual files under these paths. Return a DRAFT CARD BODY ONLY (no frontmatter),
≤60 lines, in exactly this format:

<Purpose — what this module is for, ≤2 lines>

## Key files
- `path/to/file` — one-line role

## How it works
(≤15 lines — the mental model, not a file tour)

## Invariants & gotchas
- things that must stay true; traps that would bite

## Interfaces
**Depends on:** [[other-module]], …
**Used by:** [[other-module]], …

Ground every claim in files you actually read; anchor invariants/gotchas to the file
that makes them true. Record JUDGMENT (mental models, invariants, why) — never
inventories grep/ls can regenerate (full function lists, file trees); those rot fastest.
Unknown = omit the line. Never guess or speculate.
```

## 3. Write the cards

For each returned draft: review for obvious nonsense (wrong language, invented files, generic filler) — fix or re-dispatch if bad. Then write `.claude/memory/atlas/<module>.md`:

```yaml
---
module: <kebab-name>          # matches filename
paths:
  - <globs from step 1>
verified: <captured HEAD sha, or 0000000>
verified_date: <today, YYYY-MM-DD>
---
<draft body>
```

Then fix cross-card wikilinks: every name in **Depends on:** / **Used by:** must match a real card filename in `atlas/` (`[[auth]]` → `atlas/auth.md`). Rename or drop links that don't resolve.

## 4. Rewrite MEMORY.md

Edit `.claude/memory/MEMORY.md`:
- DELETE the `> **STATUS: EMPTY — run /mem-init …**` blockquote and the one-liner HTML comment placeholder.
- Write a real one-line project description in their place.
- Fill the `## Atlas` table — replace the `*(empty — run /mem-init)*` placeholder row:
  - **≤20 cards:** one row per card: `| [[<module>]] | <one-line scope> | ✓ <today YYYY-MM-DD> |`
  - **>20 cards:** hierarchical — write one `atlas/INDEX-<area>.md` per area from step 1
    (shape of `atlas/_index.md`: one-line area summary + the per-card table), and give the
    master table one row per area: `| [[INDEX-<area>]] | <summary> (N cards) | ✓ <today> |`.
    Sessions climb master → area index → card.
- PRESERVE the `## Protocol` section (every numbered rule, however many there are) and `## Where everything lives` VERBATIM — never reword them.
- Total file ≤120 lines.

## 5. Optional task seed (ask first — never do silently)

Offer: "Want me to scan TODO/FIXME comments into tasks.md ## Later?" Only on yes: grep `TODO|FIXME`, add one bullet per finding with `file:line` under `## Later` in `.claude/memory/tasks.md` — cap at 30 bullets; if more exist, add one line "(+N more TODO/FIXME in code — grep for the rest)".

## 6. Report

- Cards written (name + paths each).
- Partition rationale in 2 lines.
- Anything needing human review: weak drafts, dropped globs, areas left uncovered.
