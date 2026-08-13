---
module: engram-hooks
paths:
  - engram/template/hooks/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Three hooks that surface Engram memory health inside Claude Code sessions — brief,
auto-capture, status line — each shipped as a bash + PowerShell twin for cross-platform installs.

## Key files
- `engram/template/hooks/engram-brief.sh` / `.ps1` — SessionStart hook: prints the session brief (tasks, recent journal, atlas/architecture staleness) from stdin JSON
- `engram/template/hooks/engram-capture.sh` / `.ps1` — PreCompact/SessionEnd hook: drafts a journal entry via headless `claude -p` and appends it to today's journal
- `engram/template/hooks/engram-statusline.sh` / `.ps1` — statusLine command: renders task/atlas/journal health in the status bar

## How it works
All three read a JSON payload from stdin and resolve the project root from
`CLAUDE_PROJECT_DIR` → payload cwd → `$PWD`, then resolve the Engram root (since
2026-08-11, shared by all three): root itself → `.claude/engram-root` pin file (first
non-empty line = relative child path; dangling pin falls through) → probe one level down
for `*/.claude/memory/MEMORY.md` (first match) → not-installed exit. Brief tags its
header `(child)` when pin/probe resolved; capture's journal write follows the resolved
root; statusline prefixes `child:` as before. `jq` is never
assumed: bash extracts flat JSON fields with grep/sed, PowerShell uses ConvertFrom-Json;
JSON-escaped backslashes in Windows paths are collapsed back. Staleness logic (shared by
brief and statusline) parses card frontmatter and runs `git log <verified>..HEAD -- <paths>`;
missing/zero `verified` = unknown baseline = stale. The statusline caches its atlas pass in
the OS temp dir keyed by HEAD sha + card-list checksum, invalidated when a card mtime is
newer. Capture spawns `claude --bare -p --model claude-haiku-4-5 --allowedTools Read` on the
transcript, demanding either `SKIP` or an exactly-formatted `## HH:MM — headline [model ·
auto-draft]` entry, validated before appending.

## Invariants & gotchas
- Every hook must ALWAYS exit 0 and never write stderr — `main 2>/dev/null; exit 0` (bash)
  / outer try/catch (ps1); failures silently skip a section, never error the session.
- Capture guards re-entry via `ENGRAM_CAPTURE=1` + `claude --bare`; skips SessionEnd on
  `reason=resume`, transcripts <80KB, or a journal entry within the last 2h. PreCompact has
  no such heuristics by design.
- Brief output hard-caps at 80 lines.
- Statusline registers per-USER (`~/.claude/settings.json`), never per-project (singleton);
  it self-locates via the same pin/probe resolution as brief/capture.
- The twins must stay behaviorally identical; ps1 files stay pure ASCII (unicode built from
  char codes) for PS 5.1. On Windows the `.ps1` twins do the real work (since 2026-08-11):
  install.ps1 registers the ps1 statusline directly, and brief/capture `.sh` detect
  msys/cygwin via `$OSTYPE` and exec their ps1 twin — the committed settings.json keeps the
  cross-platform bash registration. Git Bash spawns can cost ~1s EACH (see gotchas).
- PowerShell `-like` treats `*` as a wildcard: bash glob `'* '*` (asterisk bullet) must port
  as `'[*] *'`, NOT `'* *'` (matched every line containing a space — overcounted tasks).

## Interfaces
**Depends on:** [[engram-memory-format]]
**Used by:** [[engram-installer]]
