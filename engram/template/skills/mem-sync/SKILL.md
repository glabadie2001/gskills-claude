---
name: mem-sync
description: Repair pass for Engram memory — re-verify stale atlas cards against git history, compact old journal entries, prune done tasks, rebuild the MEMORY.md Atlas TOC, and enforce line budgets.
argument-hint: [--full]
when_to_use: When the SessionStart brief shows stale cards, before starting major work on a stale module, or weekly as maintenance. Pass --full to also create cards for uncovered code areas instead of just reporting the gaps.
---

# mem-sync — repair memory rot

All paths relative to repo root; memory in `.claude/memory/`.

## 0. Setup

- `.claude/memory/MEMORY.md` missing → stop: "Engram not installed." Contains `STATUS: EMPTY` → stop: "Not initialized — run /mem-init first."
- Capture once: `git rev-parse --short HEAD` → `<HEAD>`, and today's date. Not a git repo → skip steps 1–2 (staleness needs git), still do 3–6.

## 1. Staleness sweep

For every `atlas/*.md` EXCEPT `_*.md` (templates, never real cards):

1. Parse `paths` (glob list) and `verified` (short sha) from frontmatter.
2. Check the sha still exists: `git cat-file -t <verified>`. Fails (rebase/history rewrite/`0000000`) → treat card as FULLY STALE: re-verify the whole body against current code (no diff to guide you).
3. Else `git log --oneline <verified>..HEAD -- <path1> <path2> …` → N commits.
   - **N=0 → fresh.** Do NOT touch the card. Do NOT bump `verified` or `verified_date` — a card is "fresh as of its own verified_date"; bumping the sha without re-checking the body is lying. TOC row keeps `✓ <verified_date>`.
   - **N>0 → stale.** Read the log messages, then `git diff <verified>..HEAD --stat -- <paths>`, then targeted reads of the files that changed. Update the card body IN PLACE — edit wrong claims directly, never append contradictions below stale text. Set `verified: <HEAD>`, `verified_date: <today>`.

**Fan-out rule:** if >5 cards are stale, dispatch one `general-purpose` agent per stale card in parallel, explicit `model: sonnet`. Paste into each prompt: the full current card text, its git log + `--stat` output, and instructions to read the changed files and return the complete updated card (frontmatter with `verified: <HEAD>` / `verified_date: <today>` + body, ≤60 lines, corrections in place). The orchestrator writes the files and MUST sanity-check every returned body before writing: frontmatter schema intact, sections in order Purpose / Key files / How it works / Invariants & gotchas / Interfaces, ≤60 lines, no appended contradictions. Bad body → fix inline or re-dispatch once.

## 1b. Dead-reference lint

For every card (stale or fresh): check its `paths:` globs still match at least one file
(`git ls-files <glob>`); check the files named in `## Key files` still exist. A glob
matching nothing means the module moved or died — staleness detection is silently broken
for that card: re-anchor the globs to the module's new location (or flag the card for
deletion if the module is gone). Vanished Key-files entries → fix in place. Dead
references are the #1 cause of memory-induced wrong edits; never leave one standing.

## 2. Coverage check

List top-level source dirs. Any significant code area matched by NO card's `paths`:
- **with `--full`** → create cards for it via the mem-init pattern: `Explore` agent per gap, explicit `model: sonnet`, same card format, `verified: <HEAD>`, `verified_date: <today>`.
- **without** → report the gap in step 6; do not create.

## 3. Journal compaction

For each `journal/YYYY-MM-DD.md` (exclude `_template.md`) dated more than 14 days ago:

1. **Idempotency:** skip the day if `## YYYY-MM-DD` already appears in `journal/archive/YYYY-MM.md`.
2. Append to `journal/archive/YYYY-MM.md` (create if missing):

   ```
   ## YYYY-MM-DD
   - <headline of each entry, one bullet per entry>
   - **Learned:** <preserved VERBATIM from the entries>
   - **Dead ends:** <preserved VERBATIM — highest-value content, never paraphrase or drop>
   ```

   **Did** and **Touched** bullets may be dropped. **Learned** and **Dead ends** must survive verbatim.
3. Delete the original daily file.

## 4. Task pruning

In `.claude/memory/tasks.md`: delete `## Done (recent)` items whose `(YYYY-MM-DD)` suffix is more than 14 days ago (undated Done items: add today's date instead of deleting). The journal keeps the story — no other section is pruned.

## 5. Rebuild MEMORY.md Atlas TOC

Regenerate the `## Atlas` table from the actual `atlas/` directory (excluding `_*.md`):
- Add rows for new cards; drop rows whose card file no longer exists.
- Freshness markers: `✓ <verified_date>` for fresh and re-verified cards; `⚠ N commits behind` for any card left stale (e.g. a fan-out agent failed twice, or gaps reported without `--full`).
- PRESERVE the project one-liner, `## Protocol`, and `## Where everything lives` VERBATIM.
- Budgets: MEMORY.md ≤120 lines. Any card >60 lines → trim least-load-bearing content (verbose How-it-works prose first; never cut Invariants & gotchas).
- Atlas >~20 cards → consolidate: merge closely-related cards along a coarser architectural seam (union their `paths`, keep every invariant/gotcha, re-verify the merged body, `verified: <HEAD>`). A crowded index is how the right card stops being found.

## 6. Report

- Table: card → `fresh` / `re-verified (N commits)` / `created` / `still stale`.
- Journals compacted (count of days archived + files deleted).
- Done tasks pruned (count).
- Coverage gaps (and whether `--full` filled them).
