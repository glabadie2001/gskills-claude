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

1. **Index.** Read `.claude/memory/MEMORY.md`. From its Atlas table, pick candidate cards for the question.
2. **Search.** Grep `.claude/memory/` for keywords from the question — ALL layers: `atlas/`, `journal/` (including `journal/archive/`), `decisions/`, `gotchas.md`, `tasks.md`. Journal dead-ends and ADRs often hold the "why" that cards don't.
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
