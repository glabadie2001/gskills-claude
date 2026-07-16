# Engram — a memory engine for Claude Code sessions

*An engram is the physical trace a memory leaves in a brain. This is that, for a codebase.*

## The problem

Every Claude Code session starts amnesiac. It rereads the same files, rediscovers the same
gotchas, re-makes (or worse, un-makes) the same decisions, and repeats dead ends that a
previous session already paid for. CLAUDE.md helps but it is static, hand-maintained, and
says nothing about *what happened* — only what is.

## Design axiom

A memory system for an LLM doesn't fail by being badly formatted. It fails in exactly five
ways. Every mechanism in Engram exists to counter one of them:

| # | Death mode | Counter-mechanism |
|---|------------|-------------------|
| 1 | **Write-nothing** — sessions end without capture; memory stays empty | Journal-at-milestones protocol in the always-loaded index (capture happens DURING work, so compaction/session death can't destroy it); a post-compaction hook check that catches anything still unlogged; capture skills that cost seconds, not minutes |
| 2 | **Stale-confident** — docs assert things the code no longer does; wrong context is worse than none | Every atlas card records the git SHA it was verified against; staleness is *computed* (`git log <sha>..HEAD -- <paths>`), never guessed; `/mem-sync` repairs; the index shows freshness markers |
| 3 | **Bloat** — memory grows until loading it costs more than rereading the code | Hard line budgets per file; one always-loaded file (the index), everything else pull-based; journals older than 14 days compact into monthly digests |
| 4 | **Write-only** — memory exists but no session ever reads it | The index is force-loaded via CLAUDE.md import; a SessionStart hook injects the last journal entries + open tasks + staleness summary; `/mem-recall` defines a memory-first retrieval protocol |
| 5 | **Fragmentation** — the same fact lives in three places and drifts three ways | Single-home rule: every fact has exactly one home layer chosen by *volatility*; everything else links to it with `[[wikilinks]]` |

## Layers, by volatility

Facts are stored by *how fast they change*, because that determines the write discipline:

```
.claude/memory/
  MEMORY.md          # THE INDEX — always loaded, hard cap 120 lines
  atlas/             # what the code IS      (slow;   edited in place, SHA-stamped)
    <module>.md
  decisions/         # why it's that way     (never;  append-only ADRs)
    NNN-slug.md
  gotchas.md         # what bites            (accumulating; dated bullets)
  tasks.md           # what's next           (living;  Now / Next / Later / Done)
  journal/           # what happened         (fast;   append-only, daily files)
    YYYY-MM-DD.md
    archive/YYYY-MM.md   # monthly digests of compacted journals
```

**Single-home rubric:** Is it about what the code *is*? → atlas. About *why* a choice was
made? → decision. A trap that will bite again? → gotcha (module-specific traps go in that
module's atlas card; cross-cutting ones in gotchas.md). Something *to do*? → task.
Everything else — narrative, progress, dead ends — is journal.

### MEMORY.md (the index)

The only file loaded into every session (via `@.claude/memory/MEMORY.md` in CLAUDE.md).
Contains, in order: project one-liner · the usage protocol (below) · atlas table of
contents with freshness markers · Now/Next tasks · pointers. **Hard cap: 120 lines.**
Nothing else is always-loaded; the index buys its tokens by making everything else findable.

### Atlas cards (living documentation)

One card per module/subsystem. Frontmatter:

```yaml
---
module: auth                       # kebab-case, matches filename auth.md
paths:                             # globs that define this module's footprint
  - src/auth/**
  - middleware/session.ts
verified: a1b2c3d                  # git SHA the body was last checked against
verified_date: 2026-07-16
---
```

Body sections (fixed order): **Purpose** (2 lines) · **Key files** (path → one-line role) ·
**How it works** (the mental model, ≤15 lines) · **Invariants & gotchas** (things that must
stay true; things that bite) · **Interfaces** (depends on / used by, as `[[wikilinks]]`).
Cap ~60 lines/card. Cards are *edited in place* — never append contradictions.

`paths` + `verified` make staleness mechanical: commits in `git log <verified>..HEAD -- <paths>`
mean the card needs re-verification. The index TOC shows `✓` (fresh) or `⚠ N commits behind`.

### Journal (activity log)

`journal/YYYY-MM-DD.md`, append-only entries:

```markdown
## 14:32 — Fixed token-refresh race
- **Did:** serialized refresh behind a mutex in `src/auth/refresh.ts`
- **Learned:** the SDK retries 401s internally — our retry doubled it
- **Dead ends:** tried debouncing at the caller; fails because two tabs share no state
- **Touched:** `src/auth/refresh.ts`, `src/auth/refresh.test.ts`
- **Next:** [[auth]] card updated; consider e2e test for multi-tab
```

**Dead ends are first-class.** "We tried X and it fails because Y" is the highest-value
memory a session can leave — it is the only thing that prevents *repeating* work rather
than merely speeding it up.

### Tasks, decisions, gotchas

`tasks.md`: `## Now` / `## Next` / `## Later` / `## Done (recent)`; each task one line +
optional context links. Done items older than 14 days are pruned by `/mem-sync` (the
journal already has the story). `decisions/NNN-slug.md`: Decision / Context / Alternatives
rejected / Consequences — append-only, never edited, superseded by a new ADR that links
back. `gotchas.md`: dated bullets with file refs.

## The protocol (always loaded, in MEMORY.md)

1. **Read before exploring.** Before opening code to answer "how does X work", check the
   atlas TOC (live freshness comes from the session brief). Fresh card → trust it. Stale
   card → use it as a map, verify claims you rely on, fix wrong ones in place — but bump
   its SHA only after re-checking the whole card; partial checks leave the SHA for
   /mem-sync.
2. **Write at milestones, not at the end.** Finished a task, fixed a bug, learned something
   non-obvious, hit a dead end → append a journal entry *then* (30 seconds), and touch the
   affected atlas card / gotchas / tasks. Sessions die without warning; end-of-session
   capture is capture that never happens.
3. **Update in place, link, don't duplicate.** One home per fact; `[[wikilinks]]` elsewhere.
4. **Respect budgets.** Index ≤120 lines; cards ≤60; trim as you write, not "later".
5. **Trust order: code > fresh atlas & decisions > journal.** Agent-written journal notes
   are leads, not truth; `(per user, date)` marks direct user directives, which outrank
   inference.

## Write paths (skills)

| Skill | What it does |
|---|---|
| `/mem-init` | Bootstrap: fan out exploration over the codebase, write the initial atlas + index, wire the CLAUDE.md import. Day-one value — memory starts full, not empty. |
| `/mem-journal` | Append a journal entry for work just done; update tasks.md; nudge atlas/gotchas if the work invalidated them. |
| `/mem-save` | Capture one fact; route it to its single home by the volatility rubric. |
| `/mem-sync` | Repair pass: recompute staleness for every card, re-verify stale ones against the diff, bump SHAs, rebuild the index TOC, compact old journals into monthly digests, prune Done tasks. |
| `/mem-recall` | Retrieval protocol: answer from memory first (index → card → journal grep), cite freshness, fall back to code only for gaps — then backfill the card. |

## Read paths (hooks)

- **SessionStart** — injects: last 2 journal files' recent entries, Now/Next tasks, and a
  computed staleness summary ("3 cards stale: auth (4 commits), api (1), db (2)"). This is
  the dynamic context a static import can't provide.
- **Post-compaction check** — the same SessionStart hook fires with `source: "compact"`
  immediately after a compaction and injects a reminder to journal anything not yet
  captured. (True pre-compaction injection isn't possible: PreCompact command hooks can
  only allow/block, not add context. The real defense against compaction loss is protocol
  rule 2 — capture at milestones, so there's nothing left to lose when compaction hits.)

One cross-platform hook entry is registered in `.claude/settings.json` (bash flavor — Git
Bash on Windows, native bash elsewhere — so the committed settings work for a whole team);
`engram-brief.ps1` ships as a documented fallback for PowerShell-only Windows setups.

## Field validation

A three-angle survey of the field (products, research, practitioner reports — see
[FIELD-NOTES.md](FIELD-NOTES.md)) independently confirmed the core bets: production
systems converge on markdown + hard caps over vector DBs; retrieval failure is the
dominant memory error mode (an always-loaded index removes it by construction); staleness
is the most-repeated failure everywhere and git-diff detection is what practitioners ask
for over timestamps; bootstrap-from-codebase is unsolved elsewhere. It also contributed
eight adopted deltas — epistemic trust order, dead/parked dead-ends, dead-reference
linting, judgment-not-inventory cards, evidence anchoring, a write-path poisoning guard,
an atlas growth bound, and user-directive provenance — each traceable to a documented
failure in FIELD-NOTES.md.

## What Engram is not

- **Not a vector database.** Retrieval is grep + links + a human-readable index. The corpus
  is small by construction (budgets); exact-match + structure beats embeddings at this scale,
  and every byte stays auditable and diffable in the repo.
- **Not CLAUDE.md's replacement.** CLAUDE.md stays the place for *instructions* (how to
  build, style rules). Engram holds *knowledge* (what/why/what-happened). The import line
  is the bridge.
- **Not autonomous.** Hooks inject and remind; Claude writes. Nothing writes memory except
  a model that just understood something.

## Repo layout of this engine

```
D:\AI\Memories\
  README.md            # quickstart + philosophy
  DESIGN.md            # this file
  install.ps1          # installer: copies template into a target repo, wires everything
  template\
    CLAUDE-snippet.md  # block appended to the target's CLAUDE.md
    settings-fragment.json
    memory\            # → <target>/.claude/memory/
    skills\            # → <target>/.claude/skills/
    hooks\             # → <target>/.claude/hooks/
```
