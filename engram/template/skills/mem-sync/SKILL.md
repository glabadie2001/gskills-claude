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
- **Version walk:** read `.claude/memory/VERSION` (missing → 1) and the current tooling
  version from `MIGRATIONS.md` in this skill's own directory. Memory older → apply each
  `## vN → vN+1` section of MIGRATIONS.md in order BEFORE anything else, writing the new
  number to VERSION after each and journaling the migration. Memory newer → stop: tooling
  is stale; update it (engine pull + installer `-RefreshTooling`). Never downgrade.
- Capture once: `git rev-parse --short HEAD` → `<HEAD>`, and today's date. Not a git repo → skip steps 1–2 (staleness needs git), still do 3–6.

## 1. Staleness sweep

For every `atlas/*.md` EXCEPT `_*.md` (templates) and `INDEX-*.md` (area indexes — TOCs, not cards):

1. Parse `paths` (glob list) and `verified` (short sha) from frontmatter.
2. Check the sha still exists: `git cat-file -t <verified>`. Fails (rebase/history rewrite/`0000000`) → treat card as FULLY STALE: re-verify the whole body against current code (no diff to guide you).
3. Else `git log --oneline <verified>..HEAD -- <path1> <path2> …` → N commits.
   - **N=0 → fresh.** Do NOT touch the card. Do NOT bump `verified` or `verified_date` — a card is "fresh as of its own verified_date"; bumping the sha without re-checking the body is lying. TOC row keeps `✓ <verified_date>`.
   - **N>0 → stale.** Read the log messages, then `git diff <verified>..HEAD --stat -- <paths>`, then targeted reads of the files that changed. Update the card body IN PLACE — edit wrong claims directly, never append contradictions below stale text. Set `verified: <HEAD>`, `verified_date: <today>`, `verified_by: <the model that re-read the code>` (your own id if inline, the fan-out agent's model if delegated, + effort if known).

**Fan-out rule:** if >5 cards are stale, dispatch one `general-purpose` agent per stale card in parallel, explicit `model: sonnet`. Paste into each prompt: the full current card text, its git log + `--stat` output, and instructions to read the changed files and return the complete updated card (frontmatter with `verified: <HEAD>` / `verified_date: <today>` + body, ≤60 lines, corrections in place). The orchestrator writes the files and MUST sanity-check every returned body before writing: frontmatter schema intact, sections in order Purpose / Key files / How it works / Invariants & gotchas / Interfaces, ≤60 lines, no appended contradictions. Bad body → fix inline or re-dispatch once.

## 1b. Dead-reference lint

For every card (stale or fresh): check its `paths:` globs still match at least one file
(`git ls-files <glob>`); check the files named in `## Key files` still exist. A glob
matching nothing means the module moved or died — staleness detection is silently broken
for that card: re-anchor the globs to the module's new location (or flag the card for
deletion if the module is gone). Vanished Key-files entries → fix in place. Dead
references are the #1 cause of memory-induced wrong edits; never leave one standing.

## 1c. Architecture overview

`.claude/memory/architecture.md` present → run the same staleness check on its frontmatter (`paths` + `verified`). Stale → re-verify the **Live diagram only**, per /mem-arch `update` mode: the cards just re-verified in step 1 are the edge list; edit nodes/edges in place, bump `verified: <HEAD>` / `verified_date: <today>` / `verified_by: <your model id>`, and refresh `## Gaps` if the structure moved. **Never touch the Target diagram** — it changes only via explicit `/mem-arch target`. File missing after the version walk → report that `/mem-arch update` will bootstrap it. Its `paths:` globs get the same dead-reference lint as cards.

## 2. Coverage check

List top-level source dirs. Any significant code area matched by NO card's `paths`:
- **with `--full`** → create cards for it via the mem-init pattern: `Explore` agent per gap, explicit `model: sonnet`, same card format, `verified: <HEAD>`, `verified_date: <today>`.
- **without** → report the gap in step 6; do not create.

## 3. Journal compaction

For each `journal/YYYY-MM-DD.md` (exclude `_template.md`) dated more than 14 days ago:

1. **Idempotency:** skip the day if `## YYYY-MM-DD` already appears in `journal/archive/YYYY-MM.md`.
1b. **Outcome check (success-labeling):** for each entry with a `**Commits:**` line, check
   each sha before digesting: `git cat-file -t <sha>` fails → outcome `(gone — history
   rewritten)`; `git log --oneline --grep="<sha>"` returns a commit whose subject starts
   with "Revert" → outcome `(reverted by <that sha>)`. Append the outcome to that entry's
   headline bullet in the digest. An entry whose work was reverted has UNRELIABLE
   Learned/guidance: keep it verbatim (never rewrite) but prefix its Learned line with
   `(from reverted work:)`, and report every card the entry wikilinks under "re-verify
   skeptically" in step 6 — guidance that preceded a revert is the research-documented
   path to confidently-wrong memory.
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

## 5. Rebuild the Atlas indexes

Regenerate from the actual `atlas/` directory (excluding `_*.md`):
- **Flat atlas (≤~20 cards, no `INDEX-*.md` files):** master `## Atlas` table gets one row
  per card. Add rows for new cards; drop rows whose card file no longer exists.
- **Hierarchical atlas (`INDEX-*.md` files exist):** rebuild each `atlas/INDEX-<area>.md`
  table from its member cards (keep its one-line area summary; follow `atlas/_index.md`
  shape); master `## Atlas` table gets one row per area:
  `| [[INDEX-<area>]] | <summary> (N cards) | ✓ all fresh / ⚠ N stale |`.
  A card listed in no index → add it to the best-fit area's index (or directly to the
  master table if none fits). A card in two indexes → keep one home, drop the other.
- **Growth trigger:** the atlas is flat AND (>~20 cards OR the rebuilt MEMORY.md would
  exceed 120 lines) → introduce hierarchy: partition cards into 3–8 areas along coarse
  architectural seams, write one `INDEX-<area>.md` per area, switch the master table to
  area rows. Prefer climbing over merging — merge two cards only when they're thin
  fragments of the same seam (union `paths`, keep every invariant/gotcha, re-verify the
  merged body, `verified: <HEAD>`).
- Freshness markers: `✓ <verified_date>` for fresh and re-verified cards; `⚠ N commits behind` for any card left stale (e.g. a fan-out agent failed twice, or gaps reported without `--full`).
- PRESERVE the project one-liner, `## Protocol`, and `## Where everything lives` VERBATIM.
- Budgets: MEMORY.md ≤120 lines; area indexes ≤60. Any card >60 lines → trim least-load-bearing content (verbose How-it-works prose first; never cut Invariants & gotchas).

## 5b. Metrics — snapshot + scorecard

`.claude/memory/metrics/` missing → create it now (the v6→v7 migration normally does;
this is the self-heal). Then:

1. **Append the sync snapshot** to `metrics/events.jsonl` (append-only; create if
   missing) — one line, observable facts only, computed from the sweep you just ran:

   ```json
   {"t":"sync","ts":"YYYY-MM-DD HH:MM","model":"claude-fable-5","head":"<HEAD>","cards":12,"fresh":10,"stale":2,"mean_behind":2.5,"index_lines":98,"cards_over_budget":0,"dead_refs_fixed":1,"journal_entries_14d":9,"journal_gap_days":1}
   ```

   (`model` = your exact model id, same signature rule as journal headlines — never guess.)

   `mean_behind` = mean commits-behind across cards that were stale at the START of this
   sync (0 if none); `journal_entries_14d` = `## ` entry count across journal files dated
   in the last 14 days; `journal_gap_days` = days since the newest dated journal file.

2. **Tally recall events** (all `"t":"recall"` lines — read the file; if it exceeds
   ~400 lines, tally with grep/wc rather than reading whole): hit / verified / miss
   counts and hit rate, all-time and last-30-days; backfill conversion (misses with
   non-null `backfilled` ÷ misses); mean `files_read` and `mem_files_read` per outcome;
   `dead_end_cited` count. **Per-model slice:** when events span more than one `model`,
   also tally hit rate and mean files-read PER MODEL — memory quality is model-relative
   (a card one model must re-verify, a stronger model trusts; a gap one model hits,
   another crushes), and per-model rows are what show whether the memory still earns its
   overhead as models progress. **Repeat-miss check:** two+ misses on the same topic
   (judge by question similarity, not exact match) = the backfill loop failed — flag it
   in the report and fix the gap now (write the missing card).

3. **Regenerate `metrics/scorecard.md`** — a GENERATED file (marked as such in a
   comment), overwrite freely, ≤40 lines: retrieval table (windows × hit/verified/miss/
   hit-rate/backfill-rate/mean-files-read), a per-model table when >1 model appears
   (model × recalls/hit-rate/mean files_read/mean mem_files_read), a one-line **cost
   ledger** — fixed overhead (index lines, always loaded) · marginal overhead (mean
   mem_files_read per recall) · benefit (mean files_read on misses minus on hits, ×
   hit count) — dead-end-save count, repeat-miss list (or "none"), then a health-trend
   table of the last 6 sync snapshots (date, HEAD, cards, fresh, mean behind, index
   lines, entries 14d). No wikilinks in this file — it is derived data, not a
   knowledge layer.

4. **Compaction:** only when `events.jsonl` exceeds ~400 lines, MOVE lines older than 90
   days verbatim into `metrics/archive/events-YYYY.jsonl` (create dirs as needed).
   Never delete or rewrite an event — recall events are the replay corpus for future
   with/without-memory experiments, and their `q` + `head` fields are only useful intact.

## 6. Report

- Table: card → `fresh` / `re-verified (N commits)` / `created` / `still stale`.
- Architecture overview: `fresh` / `re-verified` / `missing — run /mem-arch update`.
- Scorecard headline: recalls all-time, hit rate (30d), repeat misses flagged (if any).
- Index structure: flat, or which areas (and whether hierarchy was introduced this run).
- Migrations applied this run (old → new version), if any.
- Reverted/gone work found during compaction, and the cards flagged "re-verify skeptically".
- Journals compacted (count of days archived + files deleted).
- Done tasks pruned (count).
- Coverage gaps (and whether `--full` filled them).
