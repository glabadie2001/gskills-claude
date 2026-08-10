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
`CLAUDE_PROJECT_DIR` → payload cwd → `$PWD`, then locate `.claude/memory`. `jq` is never
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
  it self-locates and probes one directory level down for nested Engram installs.
- The twins must stay behaviorally identical; ps1 files stay pure ASCII (unicode built from
  char codes) for PS 5.1. On Windows the `.sh` twin is the default registration (Git Bash);
  `.ps1` is the documented fallback.

## Interfaces
**Depends on:** [[engram-memory-format]]
**Used by:** [[engram-installer]]
