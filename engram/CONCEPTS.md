# Engram concepts — designed, not (yet) built

Ideas that survived a design discussion and deserve to keep their reasoning.
Each entry states the problem, the shape of the answer, and the tax it pays.
When one gets built, its entry moves into DESIGN.md; when one gets rejected,
it stays here with the rejection noted (a dead end recorded is a dead end
not repeated).

## Hub-and-spoke memory reconciliation ("central server sync") — 2026-08-10

**Problem.** Engram is single-writer-first. With memory committed to git,
multi-user teams get merge conflicts resolved by *whoever happens to hit
the merge* — the least-context person at the worst moment — and duplicate
gap discovery (two users independently exploring what memory doesn't yet
hold) goes undetected for the lifetime of a feature branch.

**Shape.** Spokes and a hub, reconciled on a cadence:

- **Spokes:** every user keeps a raw, uncommitted working memory all day —
  the pre-git feel. At session end (or via cron) the delta lands on a
  personal memory branch (`mem/<user>`).
- **Hub:** a git remote, NOT a bespoke server. A server is either dumb sync
  (last-write-wins — silent knowledge destruction; stale-confident death at
  team scale, plus lost history) or smart sync — and if it's smart, the
  intelligence is in the *reconciler*, so the server itself is just
  transport + storage, which git already is: distributed, historied,
  diffable, philosophically aligned (plain files, no external services).
- **Librarian:** a scheduled agent (nightly by default) runs /mem-sync at
  team scope: gathers spoke deltas, merges atlas card edits SEMANTICALLY —
  re-verifying conflicted claims against trunk code, which is the only
  correct arbiter — dedupes tasks, interleaves journals by timestamp, flags
  cross-user repeat misses ("you both explored billing retry on Tuesday"),
  and publishes canonical memory to trunk. Metrics events, signed per
  model (and effectively per user), are its audit trail.
- **Morning briefs** note the reconcile: "3 cards updated overnight, 1
  duplicate exploration flagged."

This fits Engram's deepest rule better than git merge drivers do: memory
operations need model judgment ("nothing writes memory except a model that
just understood something" — the same reason the installer never migrates
memory). A merge of two accounts of the auth module is an editorial act,
not a textual one.

**What it buys.** Conflict resolution moves to a dedicated reconciler with
authority, fresh context, and a predictable cadence. The duplicate-
discovery window drops from feature-branch lifetime (weeks) to one day.
Commit noise disappears from the workday entirely — spokes never commit
mid-day.

**The tax.** Decoupling memory from code branches reintroduces
branch-blindness: canonical memory becomes one shared truth describing
several divergent code states, and a spoke's card update may describe code
not yet on trunk. The librarian needs branch discipline: a delta whose
`verified` sha is not on trunk is held in a pending overlay until its code
merges. This is exactly where a naive implementation quietly corrupts the
atlas. (A `branch:` frontmatter field on cards — with linter awareness to
skip glob checks for cards whose branch isn't checked out — is the cheap
first slice, and is worth shipping even without the rest.)

**Upgrade path.** Nothing about solo usage changes: committed memory IS the
hub's substrate, and a solo user simply is the librarian. When a second
user appears, the upgrade is a personal-branch convention plus one
scheduled agent — not an architecture change. The nightly reconcile is
multi-source /mem-sync: the repair machinery exists; it needs a
"gather from N branches" input mode, not a new engine.

**Related but separable — team hardening for the pure-git path:** a merge
driver for `atlas/*.md` that keeps both bodies and zeroes `verified` (an
unresolved merge is by definition unverified; the next /mem-sync
re-verifies against merged code), MEMORY.md conflicts resolved by
regeneration (the TOC is derived data), tasks.md union-merged with a dedupe
pass at sync, and `.claude/memory/** linguist-generated=true` so PR views
collapse memory diffs. Worth building first if a team adopts the pure-git
model before the librarian exists.
