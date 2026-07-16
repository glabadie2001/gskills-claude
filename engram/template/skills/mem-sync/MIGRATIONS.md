# Engram migrations

**Current tooling version: 2.** The installed memory's version lives at
`.claude/memory/VERSION` (one integer; **missing file = version 1**). /mem-sync compares
that number against the version above and applies each `## vN → vN+1` section below in
order, writing the new number to VERSION after each section completes and appending a
journal entry noting the migration. Never downgrade: if memory is NEWER than this file,
the tooling is stale — stop and tell the user to update it (engine repo pull + installer
with `-RefreshTooling`).

Migrations touch structure and metadata only. They NEVER rewrite journal entries
(append-only), ADR bodies, or card prose.

## v1 → v2 (hierarchical indexes · model signatures · write policy)

1. **Protocol rule 6** — in `MEMORY.md`, append after rule 5, verbatim:

   ```markdown
   6. **Subagents propose; the orchestrating session writes.** Dispatched agents return
      findings — only the session holding full context commits them to memory (prevents
      write races on shared files and low-context noise). Sign what you write: journal
      headlines and `verified_by` carry the model id + effort that did the work.
   ```

2. **Atlas TOC comment** — replace the HTML comment directly above the Atlas table with:

   ```markdown
   <!-- Maintained by /mem-init and /mem-sync. One row per card in atlas/ — or, when the
        atlas outgrows this file's budget, one row per AREA ([[INDEX-<area>]] maps of
        content): climb master → area index → card.
        Freshness: ✓ = verified at last sync · ⚠ N = N commits touched its paths since. -->
   ```

3. **"Where everything lives"** — replace the `atlas/<module>.md` bullet with:

   ```markdown
   - `atlas/<module>.md` — what each subsystem is and how it works (SHA-stamped);
     `atlas/INDEX-<area>.md` — area maps the Atlas table links to when the atlas is large
   ```

4. **Card frontmatter hygiene** — for every `atlas/*.md` card (skip `_*.md`, `INDEX-*.md`):
   - Strip any inline `#` comment from frontmatter lines (v1 tooling could emit
     `module: auth  # matches filename` — the comment text corrupts pathspec parsing
     and staleness detection).
   - If `verified_by:` is absent, add `verified_by: unknown (pre-v2)` after
     `verified_date:` — do NOT invent a model id for work you didn't witness.

5. **Hierarchy** — no action here: /mem-sync step 5 introduces `INDEX-<area>.md` maps
   automatically when the atlas crosses ~20 cards.

6. **Signatures are forward-only** — journal headlines, gotcha bullets, and ADR `By:`
   lines apply to NEW writes; never retro-sign existing entries (append-only layers stay
   untouched, and a signature you didn't witness is fabricated provenance).
