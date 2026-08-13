---
name: mem-init
description: Bootstrap Engram memory for this codebase — survey the repo, partition into modules, fan out exploration agents, write atlas cards, and fill MEMORY.md so memory starts full, not empty.
when_to_use: Once per repo, right after installing Engram, while MEMORY.md still shows "STATUS: EMPTY". Never on an already-initialized repo — use /mem-sync for that.
---

# mem-init — bootstrap Engram memory

All paths in this skill mean `<ROOT>/.claude/memory/...`; `<ROOT>` is resolved in Step 0 below.

## 0. Guards

1. **Step 0 — resolve `<ROOT>`.** `.claude/memory/MEMORY.md` exists here → `<ROOT>` = `.`. Else if `.claude/engram-root` exists → `<ROOT>` = the relative path on its first line. Else if `*/.claude/memory/MEMORY.md` matches exactly one directory one level down → `<ROOT>` = that directory; several matches → pick the one the current work concerns and say so. No match → stop: "Engram not installed — run the installer first." Every path below means `<ROOT>/.claude/memory/...`, and every `git` command runs as `git -C <ROOT> ...`.
2. Read MEMORY.md. If it does NOT contain the `STATUS: EMPTY` marker → already initialized. Stop and point the user to `/mem-sync`.
3. Run `git rev-parse --short HEAD`.
   - Succeeds → capture the short sha ONCE, for `architecture.md` (step 3b) only. Cards
     do NOT get this sha: new cards are born **ASSUMED** (`verified: 0000000`) — drafting
     a card is not a verification act, and stamping HEAD would mint unearned trust (a ✓
     nothing ever checked anything against). The first `/mem-sync` attests each card and
     mints its footprint manifest.
   - Fails but `git rev-parse --git-dir` succeeds → a git repo with NO commits yet: fine —
     cards are born `verified: 0000000` regardless; /mem-sync baselines after the first commit.
   - Both fail (not a git repo) → warn: staleness tracking disabled.

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
module: <kebab-name>
paths:
  - <globs from step 1>
verified: 0000000
verified_date: <today, YYYY-MM-DD>
verified_by: <exact model id of the Explore agent that drafted it> (drafted, unverified)
---
<draft body>
```

(`module` must match the filename. NO inline `#` comments in the frontmatter — parsers
treat them as glob text. `verified: 0000000` is deliberate — the card is ASSUMED until a
`/mem-sync` verification act earns the stamp; never write a real sha here. `verified_by`
credits whoever drafted the card, so later sessions can weight their trust. Do NOT create
`atlas/<module>.manifest` files — manifests are minted by `engram-manifest update` at
attestation only.)

Then fix cross-card wikilinks: every name in **Depends on:** / **Used by:** must match a real card filename in `atlas/` (`[[auth]]` → `atlas/auth.md`). Rename or drop links that don't resolve.

## 3b. Draw the architecture overview

Fill `.claude/memory/architecture.md` (shipped by the installer; missing → skeleton in /mem-arch):

- **Live diagram:** derive the module graph from the cards just written — their `## Interfaces` sections are the edge list; spot-check surprising edges against code. Follow the diagram rules in /mem-arch: Mermaid `graph TD`, nodes = card names, 5–15 nodes (big repos: draw at AREA granularity, matching the step-1 areas).
- **Frontmatter:** `paths:` = union of the cards' globs (dedupe; a broad parent swallows its children — never a bare `**`); `verified:` = the captured sha; `verified_date:` = today; `verified_by:` = your model id (you assembled the graph, even if agents read the code).
- Leave Target unset and Gaps as `- *(target not set)*` — the target is the user's call; suggest `/mem-arch target` in the report.

## 4. Rewrite MEMORY.md

Edit `.claude/memory/MEMORY.md`:
- DELETE the `> **STATUS: EMPTY — run /mem-init …**` blockquote and the one-liner HTML comment placeholder.
- Write a real one-line project description in their place.
- Fill the `## Atlas` table — replace the `*(empty — run /mem-init)*` placeholder row:
  - **≤20 cards:** one row per card: `| [[<module>]] | <one-line scope> | assumed <today YYYY-MM-DD> |`
  - **>20 cards:** hierarchical — write one `atlas/INDEX-<area>.md` per area from step 1
    (shape of `atlas/_index.md`: one-line area summary + the per-card table), and give the
    master table one row per area: `| [[INDEX-<area>]] | <summary> (N cards) | assumed <today> |`.
    Sessions climb master → area index → card.
  - Never write `✓` at init — a ✓ is earned by a `/mem-sync` verification act, not by drafting.
- PRESERVE the `## Protocol` section (every numbered rule, however many there are) and `## Where everything lives` VERBATIM — never reword them.
- Total file ≤120 lines.

## 5. Optional task seed (ask first — never do silently)

Offer: "Want me to scan TODO/FIXME comments into tasks.md ## Later?" Only on yes: grep `TODO|FIXME`, add one bullet per finding with `file:line` under `## Later` in `.claude/memory/tasks.md` — cap at 30 bullets; if more exist, add one line "(+N more TODO/FIXME in code — grep for the rest)".

## 6. Report

- Cards written (name + paths each) — note they are ASSUMED (drafted, never verified):
  the brief will label them so until the first `/mem-sync` attests them and mints manifests.
- Partition rationale in 2 lines.
- Architecture overview: Live diagram drawn (node count); remind that the Target is unset — `/mem-arch target` records the idealized architecture.
- Anything needing human review: weak drafts, dropped globs, areas left uncovered.
