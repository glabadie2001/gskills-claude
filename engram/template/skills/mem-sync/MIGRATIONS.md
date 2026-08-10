# Engram migrations

**Current tooling version: 7.** The installed memory's version lives at
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

## v4 → v5 (composable modules; bug-sweep extracted from core)

The adversarial-review campaign schema (`sweeps/` ledger + `bug-classes.md`
taxonomy) is now the opt-in **bug-sweep module** (engine repo:
`modules/bug-sweep/`), applied via the installer's `-Modules bug-sweep` /
`--modules bug-sweep` flag — additive, never clobbers, works on existing
installs. This hop only reconciles memories that already carry the schema:

1. **Module already adopted?** If `sweeps/INDEX.md` or `bug-classes.md` exists
   (pioneered ad-hoc or installed earlier):
   - Ensure `sweeps/artifacts/` exists.
   - If ONE of the two module files is missing, add it by re-running the module
     installer against this repo (`install.ps1 -Target <repo> -Modules bug-sweep`
     from the engine checkout — the same checkout this tooling refresh came from).
   - Ensure MEMORY.md's "Where everything lives" carries both module bullets AS
     MARKDOWN LINKS. A backtick-only bullet (`` `bug-classes.md` ``,
     `` `sweeps/INDEX.md` ``) counts as present but unlinked: convert just its
     path token to `[bug-classes](bug-classes.md)` / `[sweeps/INDEX](sweeps/INDEX.md)`,
     keeping the project's own wording. Missing entirely → the module installer's
     snippet step adds them.

2. **Loose ad-hoc campaign artifacts but no module?** If review artifacts exist
   outside memory (e.g. `Codex_Prompt_*` / `*_Findings_*` / `*_VERIFIED*` in the
   repo root or its parent) without `sweeps/`, tell the user the bug-sweep module
   gives them a canonical durable home and offer the module install plus
   archiving. Copy, never move, without explicit approval; a prompt for a round
   that has NOT run yet stays outside the repo (a working-tree review must never
   read its own instructions).

3. **Neither?** No action — this hop changes nothing for memories without a
   campaign. Note the module's availability in the migration journal entry.

4. **Linking convention (forward-only)** — new ledger rows link artifacts and
   journal days with RELATIVE markdown links and cite class ids from
   `bug-classes.md`; never rewrite existing rows to conform.

## v5 → v6 (bug-sweep: deliberate-designs ledger + brief-based prompt archiving)

Round prompts are no longer archived whole: their accumulating sections now
have canonical homes ("Ground already covered" is derived from the INDEX;
"Deliberate designs" lives in `sweeps/deliberate-designs.md`), the archived
artifact per round is the BRIEF (per-round unique material only), and full
prompts are assembled at run time by `/codex-review`. Applies only to
memories with the bug-sweep module (`sweeps/INDEX.md` exists); otherwise no
action — note the change in the migration journal entry and move on.

1. **Create `sweeps/deliberate-designs.md`** — skip if present. If a
   campaign has run, seed it from the LATEST round prompt's "Deliberate
   designs — do not report as bugs" section (staged or archived — the
   newest is the superset), reshaped to the file's conventions (provenance
   ref per entry, one-to-three lines each); grep a few older prompts for
   entries dropped along the way and restore any still-valid ones. No
   campaign yet → install the module skeleton
   (`modules/bug-sweep/memory/sweeps/deliberate-designs.md`).

2. **INDEX conventions** — replace the conventions bullets about
   `artifacts/` naming with the module template's current ones (brief-based
   archiving, `artifacts/cold/`, deliberate-designs pointer). Conventions
   are format spec, not user data — safe to overwrite; the rows themselves
   are never rewritten except as step 3 says.

3. **Cold-store superseded full prompts (destructive — needs explicit user
   approval; skip entirely if declined, the schema works either way):**
   pack all archived full-prompt files into
   `artifacts/cold/round-prompts-<range>.tar.gz`, VERIFY the archive lists
   every packed file, delete the originals, and update each affected row's
   prompt LINK to point at the tarball (link text stays; this is the one
   sanctioned row edit — an unfixed link is a dead link, which the linter
   escalates under `sweeps/`). Findings, sweep scripts, and result JSONs
   stay uncompressed — they are small, unique, and read during triage.

4. **MEMORY.md bullet** — ensure "Where everything lives" carries the
   deliberate-designs bullet from the module's `MEMORY-snippet.md`; keep
   the project's own wording if a variant already exists.

5. **Forward-only** — never reconstruct briefs for already-run rounds; the
   cold tarball is their record. The first post-migration round archives
   the first brief.

## v6 → v7 (metrics: recall/sync event log + scorecard)

Engram now measures itself: /mem-recall appends one event per question to
`metrics/events.jsonl` (outcome hit/verified/miss, the model that answered,
cards used, source AND memory files read — and the verbatim question + HEAD
sha, which doubles as a replay corpus for future with/without-memory
experiments), and /mem-sync step 5b appends a health snapshot per run and
regenerates `metrics/scorecard.md` (hit rates sliced per model, plus a
fixed/marginal-overhead vs. benefit cost ledger).

1. **Create `metrics/`** — skip if `.claude/memory/metrics/` exists.
   Otherwise create it containing a placeholder `scorecard.md`:

   ```markdown
   # Engram scorecard
   <!-- GENERATED by /mem-sync from metrics/events.jsonl — do not hand-edit. -->

   *No data yet — /mem-recall logs events; /mem-sync builds this scorecard.*
   ```

2. **MEMORY.md bullet** — skip if a `metrics/` bullet is already present in
   "Where everything lives". Otherwise append after the `gotchas.md` bullet,
   verbatim:

   ```markdown
   - `metrics/` — self-measurement: `events.jsonl` (append-only recall/sync events;
     doubles as the replay corpus) + `scorecard.md` (generated by /mem-sync)
   ```

3. **Forward-only** — never fabricate events for recalls or syncs you did not
   witness; history starts at zero. The sync run that walks this migration
   writes the first snapshot in its own step 5b.

