---
name: mem-recall
description: Answer questions about this codebase from Engram project memory first — read the atlas and journal, check freshness against git, verify only what's stale — instead of re-exploring code from scratch. Use when the user asks how something works, where something lives, why it is the way it is, or what was tried or decided before.
when_to_use: Invoke when the user asks a question whose answer lives in a memory layer — "how does X work" (atlas), "why is Z like this" (decisions), "what was tried, what dead-ended" (journal) — or before code exploration whose goal is understanding that memory may already hold. NOT for questions a live query answers authoritatively — git state ("did we push X?", "is Y on master?"), current file contents, test output: answer those from the tool directly, no skill, no event. Git answers whether/when; memory answers why and what-it-was-like. Memory + targeted verification beats full re-exploration — that is the point of the system.
argument-hint: <the question>
---

# /mem-recall — memory-first retrieval

Question: $ARGUMENTS

## 0. Guard

**Step 0 — resolve `<ROOT>`.** `.claude/memory/MEMORY.md` exists here → `<ROOT>` = `.`. Else if `.claude/engram-root` exists → `<ROOT>` = the relative path on its first line. Else if `*/.claude/memory/MEMORY.md` matches exactly one directory one level down → `<ROOT>` = that directory; several matches → pick the one the current work concerns and say so. No match → say "Engram is not installed here (no .claude/memory/)" and answer from code as usual. Every memory path below means `<ROOT>/.claude/memory/...`, and every `git` command runs as `git -C <ROOT> ...`.

Prefer memory plus targeted verification over full code re-exploration. Read code only where memory has no answer or a stale card forces re-verification of a claim you are about to assert.

Scope guard: this skill serves questions whose answer lives in a memory layer (atlas / decisions / journal / gotchas / tasks). A question a live query answers authoritatively — git state ("did we push X?"), current file contents, test results — is NOT a recall: answer it from that tool directly, skip this procedure, log nothing. If it then turns out to hinge on narrative memory ("why was it done that way?"), enter this procedure at that point. The event log measures memory's contribution, not question traffic — logging non-memory questions corrupts the metric in both directions (inflated hit rate, inflated overhead).

## Procedure

1. **Index.** Read `.claude/memory/MEMORY.md`. From its Atlas table, pick candidate cards for the question. If a row is an area (`[[INDEX-<area>]]`), read that index file and pick candidates from its table — climb master → area → card; read only the cards you shortlist. A system-shape question ("how do the pieces fit", "what talks to what") → also read `architecture.md`: its Live diagram is the map, and its frontmatter gets the same freshness check as a card (step 4).
2. **Search.** Grep `.claude/memory/` for keywords from the question — ALL layers: `atlas/`, `journal/` (including `journal/archive/`), `decisions/`, `gotchas.md`, `tasks.md`, plus any module layers present (e.g. bug-sweep's `bug-classes.md` and `sweeps/` campaign ledger + archived review artifacts). Journal dead-ends and ADRs often hold the "why" that cards don't.
3. **Read.** Read the matched atlas cards and the journal/decision hits.
4. **Freshness check** — run the deterministic status ONCE and read the line of every
   card the answer will rely on: `.claude/scripts/engram-manifest.ps1 status` (Windows) /
   `.claude/scripts/engram-manifest.sh status` (mac/Linux):
   - `VERIFIED` → trust its claims.
   - `DRIFTED (N changed/added/removed)` → trust it EXCEPT claims that could involve the
     delta files: read the current code behind each such load-bearing claim and verify it
     BEFORE asserting it in the answer.
   - `ASSUMED` / `NOMANIFEST` / `unknown baseline` → map, not truth: verify load-bearing
     claims against code before asserting them.
   - Script missing (pre-v9 tooling) → fall back to `git log --oneline <verified>..HEAD
     -- <paths>`: empty = trust, non-empty = verify as above.
5. **Answer.** Answer the question, citing every memory source with its freshness, e.g.:
   - `[[auth]] (VERIFIED)`
   - `[[auth]] (DRIFTED — re-verified refresh flow against current code)`
   - `[[adr-003]]`, `journal 2026-07-02`
6. **Backfill.** If memory could not answer and you had to read code: write what you learned back into memory NOW, before finishing the turn. Update the relevant atlas card, or create one from the `atlas/_template.md` shape (kebab-case filename, `paths:` globs covering the module) per the /mem-save mechanics. Apply the SHA-bump rule: after editing an atlas card, bump `verified` to `git rev-parse --short HEAD` and `verified_date` to today ONLY IF (a) you actually checked the card's claims against current code during this work, AND (b) the card's status line was VERIFIED before your edit. If the card was already DRIFTED/ASSUMED, edit the body but LEAVE the old sha — /mem-sync owns full re-verification. (A brand-new card you just wrote from current code gets `verified` = current HEAD.) After any legal bump or new card, regenerate its sidecar: `engram-manifest.(ps1|sh) update --card <module>` — never hand-write a manifest. A recall miss must become a memory write. State explicitly what you backfilled.
7. **Log the recall event.** Append ONE line to `.claude/memory/metrics/events.jsonl`
   (create the directory/file if missing). This is the system's self-measurement AND the
   replay corpus for future with/without-memory experiments — `q` and `head` together let
   a later session replay the exact question against the exact code state. Record
   **observable facts only** — counts and classifications you can point at in this turn's
   tool calls, never a self-assessment of how helpful memory was. Schema (one JSON object,
   one line, no pretty-printing; strip newlines from `q` and escape its double quotes):

   ```json
   {"t":"recall","ts":"YYYY-MM-DD HH:MM","model":"claude-fable-5","effort":"xhigh","head":"<git rev-parse --short HEAD>","q":"<the question, verbatim>","outcome":"hit|verified|miss","cards":["auth","billing"],"files_read":0,"mem_files_read":3,"mem_greps":0,"mem_grep_lines":0,"dead_end_cited":false,"backfilled":null}
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
   - `mem_greps` — count of search calls (Grep tool, shell grep/rg) aimed at
     `.claude/memory/**` while answering. This is the index cache-miss signal: the
     always-loaded index should route to a card by NAME, so every memory grep marks a
     question the index couldn't route — even on a `hit`, it cost a search to get there.
   - `mem_grep_lines` — total lines of output those searches returned into context,
     summed across calls (approximate; count what you saw, round freely; 0 when
     `mem_greps` is 0). The context-cost side of the grep signal (≈10 tokens/line) —
     pairs with `mem_files_read` on the overhead ledger.
   - `dead_end_cited` — true if a journaled dead end (`dead:`/`parked:`) shaped the answer.
   - `backfilled` — card name written/updated by step 6, else `null`. A `miss` with
     `backfilled: null` must be justified in your answer (e.g. question was out of scope).

   Never edit or delete existing lines — append-only, like the journal. /mem-sync tallies
   this file into `metrics/scorecard.md`.
