# Engram

**A persistent memory engine for Claude Code sessions.**

Every Claude Code session starts amnesiac: it rereads the same files, rediscovers the same
gotchas, and repeats dead ends a previous session already paid for. Engram gives a project
a durable, git-tracked memory that sessions read at startup and write as they work — living
codebase documentation, an activity journal, a task ledger, and decision records — so
context is *retrieved*, not re-derived.

An *engram* is the physical trace a memory leaves in a brain. This is that, for a codebase.

## What you get

```
<your-repo>/.claude/memory/
  MEMORY.md            # always-loaded index (≤120 lines) with the usage protocol
  atlas/<module>.md    # living docs: one card per subsystem, stamped with the git
                       #   SHA it was verified against — staleness is COMPUTED, not guessed
  journal/YYYY-MM-DD.md# append-only activity log; dead ends are first-class
  tasks.md             # Now / Next / Later / Done
  decisions/NNN-*.md   # append-only ADRs: why things are the way they are
  gotchas.md           # cross-cutting traps
```

Plus five skills and a session-start hook:

| Piece | Job |
|---|---|
| `/mem-init` | Bootstrap: explores the codebase in parallel and writes the initial atlas — memory starts **full**, not empty |
| `/mem-recall` | Answer questions from memory first; verify anything stale; backfill misses into the atlas |
| `/mem-journal` | Log what just happened (including what *failed* and why), reconcile tasks |
| `/mem-save` | File one fact into its single home |
| `/mem-sync` | Repair pass: re-verify stale cards against the git diff, compact old journals, prune tasks, rebuild the index |
| SessionStart hook | Injects a brief every session: open tasks, recent journal entries, and which atlas cards are stale (computed live from git). After a context compaction it instead reminds the session to journal anything unlogged. |

## Watch the memory live

`viewer/engram-viewer.html` is a zero-dependency, single-file memory browser: open it in
Chrome or Edge, point it at a repo with Engram installed (or the `.claude/memory/` folder
directly), and browse the index, atlas, journal, tasks, and decisions as rendered pages
with clickable `[[wikilinks]]`. It polls the folder every ~1.5 s, so while Claude works
you see each write land — changed files pulse in the sidebar, and every change is captured
as a real line diff (computed natively in the browser; the viewer caches file contents and
runs an LCS diff, no git or Engram plumbing involved). The activity feed shows +/− counts
per event and clicking any event replays its diff; when the open file changes, its diff
appears in place. Diffs are session-local (from the moment the viewer connected) — for
history before that, memory is git-tracked: `git log -p -- .claude/memory`. No server, no
install; the folder permission is remembered between sessions (one-click reconnect).
Read-only by design — it never writes to memory.

The **⬡ Graph** button switches to an Obsidian-style memory graph: every memory file is a
node (colored by layer, sized by connectivity), every `[[wikilink]]` an edge — built from
the same content cache the diffs use, so it needs no extra tooling. Drag nodes, pan, zoom,
hover to highlight a node's neighborhood, click to open the file; files Claude just wrote
pulse in place, so in graph view you can watch activity ripple through the memory.

## Install

```powershell
# Windows
.\install.ps1 -Target C:\path\to\your\repo
```
```bash
# macOS / Linux
./install.sh /path/to/your/repo
```

Then open Claude Code in the target repo and run `/mem-init` once. That's the whole setup.

The installer copies the memory template into `.claude/memory/`, the skills into
`.claude/skills/`, the hook into `.claude/hooks/`, merges the hook registration into
`.claude/settings.json` (preserving whatever is already there), and appends an import
block to `CLAUDE.md`. It is idempotent and will **never overwrite an existing memory**
(`-RefreshTooling` updates skills/hooks only).

**Upgrading:** Engram memory is versioned (`.claude/memory/VERSION`; a missing file
means v1). After refreshing tooling on an existing install, run `/mem-sync` — it
compares the memory's version against `skills/mem-sync/MIGRATIONS.md` and walks each
migration in order, journaling what it changed. The installer never migrates memory
itself; migrations need model judgment, so they live with the skill.

Requirements: the target should be a git repository (staleness tracking is git-based;
everything else works without it). The session-start hook runs under bash — on Windows
that's Git Bash, which ships with Git for Windows; a PowerShell hook variant is included
as a fallback (see `template/settings-fragment.json` for the swap).

## Why it's built this way

Memory systems for LLMs die in five known ways. Every mechanism here counters one:

1. **Write-nothing** — capture never happens → journaling is part of the always-loaded
   protocol, costs ~30 seconds via `/mem-journal`, and a post-compaction hook catches the
   moment context is about to be lost.
2. **Stale-confident** — docs assert things the code no longer does → every atlas card
   records the commit it was verified against; `git log <sha>..HEAD -- <paths>` makes
   staleness mechanical; the session brief surfaces it; `/mem-sync` repairs it.
3. **Bloat** — memory grows until loading it costs more than rereading code → hard line
   budgets (index ≤120, cards ≤60), one always-loaded file, journals compact into monthly
   digests after 14 days.
4. **Write-only** — memory exists but is never read → the index is force-loaded via
   CLAUDE.md import, the hook injects tasks + recent journal + staleness every session,
   and `/mem-recall` makes memory the first stop, code the fallback.
5. **Fragmentation** — the same fact drifts apart in three places → single-home rule:
   each fact lives in exactly one layer (chosen by how fast it changes) and is linked
   with `[[wikilinks]]` everywhere else.

No vector database, no external services: plain markdown + git, grep-able and auditable,
small by construction. See [DESIGN.md](DESIGN.md) for the full rationale.

## Day-to-day feel

- Session starts → you (and Claude) see: *"3 open tasks · yesterday: fixed the token
  refresh race, dead end: debouncing at the caller · STALE: auth card is 4 commits behind."*
- You ask "how does billing retry work?" → Claude answers from `[[billing]]` (fresh,
  verified at `e9f21c3`) without opening a single source file — or verifies exactly the
  two claims that a stale card can't guarantee.
- You finish a fix → `/mem-journal` writes six lines, moves the task to Done, and patches
  the one atlas claim the fix invalidated.
- Friday → `/mem-sync` re-verifies what drifted, digests old journals, and tells you what
  it changed.
