---
name: mem-sync
description: Repair pass for Engram memory — re-verify stale atlas cards against git history, compact old journal entries, prune done tasks, rebuild the MEMORY.md Atlas TOC, and enforce line budgets.
argument-hint: [--full]
when_to_use: When the SessionStart brief shows stale cards, before starting major work on a stale module, or weekly as maintenance. Pass --full to also create cards for uncovered code areas instead of just reporting the gaps.
---

# mem-sync — repair memory rot

All paths in this skill mean `<ROOT>/.claude/memory/...`; `<ROOT>` is resolved in Step 0 below.

## 0. Setup

- **Step 0 — resolve `<ROOT>`.** `.claude/memory/MEMORY.md` exists here → `<ROOT>` = `.`. Else if `.claude/engram-root` exists → `<ROOT>` = the relative path on its first line. Else if `*/.claude/memory/MEMORY.md` matches exactly one directory one level down → `<ROOT>` = that directory; several matches → pick the one the current work concerns and say so. No match → stop: "Engram not installed." Contains `STATUS: EMPTY` → stop: "Not initialized — run /mem-init first." Every path below means `<ROOT>/.claude/memory/...`, and every `git` command runs as `git -C <ROOT> ...`.
- **Version walk:** read `.claude/memory/VERSION` (missing → 1) and the current tooling
  version from `MIGRATIONS.md` in this skill's own directory. Memory older → apply each
  `## vN → vN+1` section of MIGRATIONS.md in order BEFORE anything else, writing the new
  number to VERSION after each and journaling the migration. Memory newer → stop: tooling
  is stale; update it (engine pull + installer `-RefreshTooling`). Never downgrade.
- Capture once: `git rev-parse --short HEAD` → `<HEAD>`, and today's date. Not a git repo → skip steps 1–2 (staleness needs git), still do 3–6.

## 1. Staleness sweep

Run the deterministic status first — never hand-compute freshness:

```
.claude/scripts/engram-manifest.ps1 status          # Windows
.claude/scripts/engram-manifest.sh status           # mac/Linux (auto-dispatches on Windows)
```

One line per card (`STATE<TAB>module<TAB>detail`), computed by set-comparing each card's
footprint manifest (`atlas/<module>.manifest`: the tracked files + blob hashes at its
`verified` commit) against the tree at HEAD, plus one aggregate DIRTY line. Handle each:

1. **VERIFIED → fresh. Do NOT touch the card.** Do NOT bump `verified` or `verified_date` — a card is "fresh as of its own verified_date"; bumping the sha without re-checking the body is lying. TOC row keeps `✓ <verified_date>`. (Content-addressed: a revert back to verified content counts as VERIFIED — correct, not a bug.)
2. **DRIFTED (N changed, N added, N removed) → re-verify.** Read `git log --oneline <verified>..HEAD -- <paths>`, then `git diff <verified>..HEAD --stat -- <paths>`, then targeted reads of the files that changed. Update the card body IN PLACE — edit wrong claims directly, never append contradictions below stale text. Set `verified: <HEAD>`, `verified_date: <today>`, `verified_by: <the model that re-read the code>` (your own id if inline, the fan-out agent's model if delegated, + effort if known). Then regenerate its sidecar — `engram-manifest.(ps1|sh) update --card <module>` — and commit card + manifest together. NEVER hand-write a manifest (linter ERROR).
3. **ASSUMED (never verified) → first attestation.** No baseline exists: verify the whole body against current code, stamp `verified: <HEAD>` (+ date/by), then `engram-manifest update --card <module>` mints the manifest.
4. **NOMANIFEST → backfill.** Attested card from a pre-manifest install. If the detail says commits touched its paths, re-verify as DRIFTED above; otherwise leave the card untouched. Either way run `engram-manifest update --card <module>` — it writes from `git ls-tree` at the card's own `verified`, so backfilling states exactly what was attested and mints no new trust.
5. **DIRTY (aggregate line) → not a card problem.** Uncommitted work under card footprints. Never attest a card or regenerate a manifest to "cover" uncommitted files — manifests state committed content only. Finish the work, commit, then sync.
6. **`verified` sha gone** (rebase/history rewrite — status shows `unknown baseline`, linter shows `bad-verified`) → treat the card as FULLY STALE: re-verify the whole body against current code (no diff to guide you), stamp fresh, regenerate the manifest.

**Fan-out rule:** if >5 cards need re-verification, dispatch one `general-purpose` agent per such card in parallel, explicit `model: sonnet`. Paste into each prompt: the full current card text, its git log + `--stat` output, and instructions to read the changed files and return the complete updated card (frontmatter with `verified: <HEAD>` / `verified_date: <today>` + body, ≤60 lines, corrections in place). The orchestrator writes the files and MUST sanity-check every returned body before writing: frontmatter schema intact, sections in order Purpose / Key files / How it works / Invariants & gotchas / Interfaces, ≤60 lines, no appended contradictions. Bad body → fix inline or re-dispatch once. After writing each accepted card, the orchestrator runs `engram-manifest update --card <module>` (agents never write manifests).

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
- **with `--full`** → create cards for it via the mem-init pattern: `Explore` agent per gap, explicit `model: sonnet`, same card format, born ASSUMED (`verified: 0000000` — drafting is not attestation; the next sync attests them and mints manifests).
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
4. **Repair inbound links.** Every archived daily was a potential link target. Grep ALL
   memory layers for references to each day you archived — relative md links
   (`journal/YYYY-MM-DD.md`, any prefix) and `[[YYYY-MM-DD]]` wikilinks — and retarget
   them to the digest: `journal/archive/YYYY-MM.md#YYYY-MM-DD` (the digest's
   `## YYYY-MM-DD` header is the anchor; drop any finer original anchor). This is a
   sanctioned edit even in never-rewrite layers (sweeps/INDEX.md rows, old journal
   entries): retargeting changes the address, not the record — and an unrepaired link is
   a dead link, which the linter escalates to ERROR under `sweeps/`. **Self-heal:** also
   scan for `journal/<date>` references whose daily file no longer exists from EARLIER
   compactions and retarget those too — runs of this skill predating this step left them
   broken.

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
- Freshness markers: `✓ <verified_date>` for VERIFIED and just-re-verified cards; `⚠ drifted` for any card left DRIFTED (e.g. a fan-out agent failed twice, or gaps reported without `--full`); `assumed <date>` for cards still awaiting first attestation.
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

   `fresh` = VERIFIED count from the step-1 status; `stale` = DRIFTED + NOMANIFEST +
   ASSUMED. `mean_behind` = mean commits-behind across cards that needed re-verification
   at the START of this sync (from their step-1 range checks; 0 if none);
   `journal_entries_14d` = `## ` entry count across journal files dated
   in the last 14 days; `journal_gap_days` = days since the newest dated journal file.

2. **Regenerate `metrics/scorecard.md` deterministically** — run the script, never
   hand-compute the tables (zero-token principle: derived stats come from the log DB,
   not from the model):

   ```
   .claude/scripts/engram-scorecard.ps1          # Windows
   .claude/scripts/engram-scorecard.sh           # mac/Linux (auto-dispatches on Windows)
   ```

   The twins emit a byte-identical `scorecard.md` (retrieval windows, per-model slice,
   cost ledger, exact repeat-miss list, health trend of the last 6 sync snapshots) from
   `events.jsonl` + the live index line count. Stat definitions live in the `.ps1`
   header. If the script is missing, the tooling install is stale — refresh it
   (installer `-RefreshTooling`); do not fall back to hand-computing. Read the
   regenerated scorecard (≤40 lines) — it feeds the report headline.

3. **Repeat-miss check (the one model-side judgment):** the scorecard lists EXACT
   repeat misses only. Additionally grep `'"outcome":"miss"'` over `events.jsonl` and
   judge SEMANTIC near-duplicates — two+ misses on the same topic phrased differently
   = the backfill loop failed. Flag it in the report and fix the gap now (write the
   missing card). Per-model slices matter when reading the scorecard: memory quality
   is model-relative — per-model rows are what show whether the memory still earns
   its overhead as models progress.

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
