---
name: mem-recall
description: Answer questions about this codebase from Engram project memory first — read the atlas, check freshness against git, verify only what's stale — instead of re-exploring code from scratch. Use when the user asks how something works, where something lives, or why something is the way it is in this repo.
when_to_use: Invoke when the user asks "how does X work", "where is Y", "why is Z like this" about THIS codebase, or before starting any code exploration whose goal is understanding that memory may already hold. Memory + targeted verification beats full re-exploration — that is the point of the system.
argument-hint: <the question>
---

# /mem-recall — memory-first retrieval

Question: $ARGUMENTS

## 0. Guard

If `.claude/memory/` does not exist in this repo, say "Engram is not installed here (no .claude/memory/)" and answer from code as usual.

Prefer memory plus targeted verification over full code re-exploration. Read code only where memory has no answer or a stale card forces re-verification of a claim you are about to assert.

## Procedure

1. **Index.** Read `.claude/memory/MEMORY.md`. From its Atlas table, pick candidate cards for the question. If a row is an area (`[[INDEX-<area>]]`), read that index file and pick candidates from its table — climb master → area → card; read only the cards you shortlist. A system-shape question ("how do the pieces fit", "what talks to what") → also read `architecture.md`: its Live diagram is the map, and its frontmatter gets the same freshness check as a card (step 4).
2. **Search.** Grep `.claude/memory/` for keywords from the question — ALL layers: `atlas/`, `journal/` (including `journal/archive/`), `decisions/`, `gotchas.md`, `tasks.md`, plus any module layers present (e.g. bug-sweep's `bug-classes.md` and `sweeps/` campaign ledger + archived review artifacts). Journal dead-ends and ADRs often hold the "why" that cards don't.
3. **Read.** Read the matched atlas cards and the journal/decision hits.
4. **Freshness check** — for EVERY card the answer will rely on:
   - Parse the card's frontmatter: `verified` (short sha) and `paths` (globs).
   - `verified` is `0000000`, missing, or not a commit in this repo → the card has no
     baseline: treat it exactly like a stale card (map, not truth).
   - Else run: `git log --oneline <verified>..HEAD -- <paths>`
   - Empty output → card is fresh; trust its claims.
   - Non-empty → the card is a map, not the truth: read the current code behind each load-bearing claim and verify it BEFORE asserting it in the answer.
5. **Answer.** Answer the question, citing every memory source with its freshness, e.g.:
   - `[[auth]] (fresh)`
   - `[[auth]] (⚠ 4 commits behind — re-verified refresh flow against current code)`
   - `[[adr-003]]`, `journal 2026-07-02`
6. **Backfill.** If memory could not answer and you had to read code: write what you learned back into memory NOW, before finishing the turn. Update the relevant atlas card, or create one from the `atlas/_template.md` shape (kebab-case filename, `paths:` globs covering the module) per the /mem-save mechanics. Apply the SHA-bump rule: after editing an atlas card, bump `verified` to `git rev-parse --short HEAD` and `verified_date` to today ONLY IF (a) you actually checked the card's claims against current code during this work, AND (b) the card was not already stale (i.e. `git log --oneline <verified>..HEAD -- <paths>` is empty apart from your own just-made changes). If the card was already stale, edit the body but LEAVE the old sha — /mem-sync owns full re-verification. (A brand-new card you just wrote from current code gets `verified` = current HEAD.) A recall miss must become a memory write. State explicitly what you backfilled.
7. **Log the recall event.** Append ONE line to `.claude/memory/metrics/events.jsonl`
   (create the directory/file if missing). This is the system's self-measurement AND the
   replay corpus for future with/without-memory experiments — `q` and `head` together let
   a later session replay the exact question against the exact code state. Record
   **observable facts only** — counts and classifications you can point at in this turn's
   tool calls, never a self-assessment of how helpful memory was. Schema (one JSON object,
   one line, no pretty-printing; strip newlines from `q` and escape its double quotes):

   ```json
   {"t":"recall","ts":"YYYY-MM-DD HH:MM","model":"claude-fable-5","effort":"xhigh","head":"<git rev-parse --short HEAD>","q":"<the question, verbatim>","outcome":"hit|verified|miss","cards":["auth","billing"],"files_read":0,"mem_files_read":3,"dead_end_cited":false,"backfilled":null}
   ```

   - `model` / `effort` — YOUR exact model id as stated in your system context, and the
     session's effort level (`null` if unknown). Never guess either — same signature
     rule as journal headlines. Memory quality is model-relative: what one model must
     verify another answers cold, so the scorecard slices hit rates per model.
   - `outcome` — `hit`: answered fully from fresh memory, zero source files opened.
     `verified`: answered from memory, but stale card(s) forced targeted code checks.
     `miss`: memory lacked the core answer; code exploration produced it (step 6 fired).
     Mixed multi-part questions: classify by the weakest source relied on (any missed
     part → `miss`).
   - `cards` — atlas card names the answer relied on (empty array on a pure miss).
   - `files_read` — count of SOURCE files opened to answer or verify (memory files
     don't count). This is the per-outcome cost signal: `miss` cost approximates the
     no-memory baseline for the same question.
   - `mem_files_read` — count of MEMORY files opened (cards, journal files, indexes —
     excluding always-loaded MEMORY.md). This is the overhead side of the ledger: memory
     is only a win while `mem_files_read` on hits stays well under `files_read` on misses.
   - `dead_end_cited` — true if a journaled dead end (`dead:`/`parked:`) shaped the answer.
   - `backfilled` — card name written/updated by step 6, else `null`. A `miss` with
     `backfilled: null` must be justified in your answer (e.g. question was out of scope).

   Never edit or delete existing lines — append-only, like the journal. /mem-sync tallies
   this file into `metrics/scorecard.md`.
