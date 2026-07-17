# Engram migrations

**Current tooling version: 4.** The installed memory's version lives at
`.claude/memory/VERSION` (one integer; **missing file = version 1**). /mem-sync compares
that number against the version above and applies each `## vN → vN+1` section below in
order, writing the new number to VERSION after each section completes and appending a
journal entry noting the migration. Never downgrade: if memory is NEWER than this file,
the tooling is stale — stop and tell the user to update it (engine repo pull + installer
with `-RefreshTooling`).

**Walk one hop at a time, in order — never skip ahead or combine hops**, even when the
end state seems obvious: later sections assume earlier ones are complete. Write VERSION
immediately after each section so an interrupted walk resumes at the right hop.

**Every step is check-first (idempotent):** before applying a step, check whether its end
state is already present (the rule already appended, the comment already replaced, the
field already added) and skip it if so. This makes a walk that died mid-section safe to
re-run — without it, a re-run would double-apply (e.g. a duplicated protocol rule).

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

## v2 → v3 (journal wikilinks + commit linkage)

1. **Replace the installed `journal/_template.md`** in its entirety with this canonical
   v3 template (it's a format spec, not user data — safe to overwrite):

   ````markdown
   <!-- Journal file format — one file per day: journal/YYYY-MM-DD.md
        Entries are APPEND-ONLY, newest at the bottom. Written by /mem-journal
        (or directly, following this exact shape). Keep entries ≤12 lines.
        Signature: every headline ends with [<exact model id> · <effort>], e.g.
        [claude-fable-5 · xhigh] — the model that did the work; omit "· effort" if unknown.
        Wikilinks: link the PRIMARY module(s) the entry is about — once, at first mention,
        in whichever line names them. Not every occurrence, not incidental modules: a link
        asserts "an atlas card holds the current truth on this."
        Commits: when a milestone ends in a commit, journal AFTER committing so the sha
        exists; never invent or guess shas. -->

   # Journal — YYYY-MM-DD

   ## HH:MM — One-line headline of what happened [claude-model-id · effort]

   - **Did:** what was accomplished, concretely — wikilink the primary module(s) once, e.g. fixed refresh race in [[example-module]]
   - **Learned:** non-obvious facts discovered (omit if none)
   - **Dead ends:** what was tried and FAILED, and why — the highest-value line in this file.
     Mark each `dead:` (don't retry — reason is permanent) or `parked:` (retry when X changes) (omit if none)
   - **Touched:** files changed
   - **Commits:** short shas this work produced, e.g. abc123f, def456a (omit if nothing committed yet — never invent)
   - **Next:** follow-ups filed to tasks.md, atlas cards updated (omit if none)
   ````

2. **Forward-only** — never edit existing journal entries to add wikilinks or commit
   shas (append-only; a sha you didn't witness being created is fabricated linkage).
   The new format applies from the next /mem-journal write.

3. If any repo-local edits were made to `mem-journal/SKILL.md` to work around the old
   under-prompting (e.g. a manually added wikilink rule), they are superseded by the
   refreshed skill — no action needed beyond the tooling refresh itself.

## v3 → v4 (architecture overview: live vs target)

1. **Create `architecture.md`** — skip if `.claude/memory/architecture.md` already
   exists. Otherwise create it from the skeleton in `mem-arch/SKILL.md` with
   `verified: 0000000`, `paths:` = the union of the atlas cards' globs (dedupe; a broad
   parent swallows its children — never a bare `**`, or journaling commits would keep it
   perpetually stale), and `target_set: (none)`. The migration creates STRUCTURE only —
   drawing the Live diagram is /mem-arch's job (step 1c of /mem-sync, or `/mem-arch
   update`, handles it right after the walk).

2. **"Where everything lives"** — skip if an `architecture.md` bullet is already present.
   Otherwise insert after the `atlas/<module>.md` bullet, verbatim:

   ```markdown
   - `architecture.md` — Live system diagram (SHA-stamped) vs Target (idealized) + explicit gap list
   ```

3. **Skills line** — in the `Skills:` pointer block at the bottom of MEMORY.md, add
   `/mem-arch (live vs target architecture)` before the `/mem-init` entry — skip if
   `/mem-arch` is already mentioned.

4. **Forward-only** — never backfill Target intent you didn't witness: the Target starts
   unset and only an explicit `/mem-arch target` conversation sets it. The Gaps section
   stays `- *(target not set)*` until then.
