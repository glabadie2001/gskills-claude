---
module: engram-installer
paths:
  - engram/install.ps1
  - engram/install.sh
  - engram/template/settings-fragment.json
  - engram/template/CLAUDE-snippet.md
  - engram/modules/README.md
  - engram/.gitattributes
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Installer for the Engram memory engine: bootstraps `.claude/memory`, skills, hooks,
settings.json hooks, CLAUDE.md, and `.gitattributes` in a target repo, plus opt-in modules.

## Key files
- `engram/install.ps1` — PowerShell installer (PS 5.1-compatible, pure ASCII).
- `engram/install.sh` — bash twin, same flags/behavior, uses `jq` for JSON merge when present.
- `engram/template/settings-fragment.json` — the hook entries grafted into target `settings.json`.
- `engram/template/CLAUDE-snippet.md` — `BEGIN/END ENGRAM` block appended to target `CLAUDE.md`.
- `engram/modules/README.md` — opt-in module contract (MODULE.md + memory/ + MEMORY-snippet.md).
- `engram/.gitattributes` — reference for the union-merge rules the installer writes into the target.

## How it works
Memory vs tooling get different clobber policies: `.claude/memory/` is copied once and never
touched again once `MEMORY.md` exists (`install.ps1:124-137`) — re-running requires
`-RefreshTooling`, and even then memory stays untouched. Skills and hooks are tooling: freely
overwritten on refresh. Hook merges into `settings.json` are idempotent via a command marker
string (`engram-brief`, `engram-capture`) searched before appending; bash falls back to
printing manual-merge instructions when `jq` is absent rather than risk corrupting JSON.
`-AutoCapture` is opt-in: grafts PreCompact + SessionEnd hooks; the fragment's
`_autocapture_hooks` key is documentation only, never merged by default. The status line is
registered in the USER's `~/.claude/settings.json`, not the project's — a per-user singleton;
one registration covers every Engram-fied repo. Modules copy a `memory/` fragment without
clobbering existing paths and append `MEMORY-snippet.md` bullets before the `Skills:` line —
additive and idempotent, so `-Modules` works standalone against an already-installed target.

## Invariants & gotchas
- Presence of `.claude/memory/MEMORY.md` is the sole "already installed" signal — deleting it
  makes the installer think it's a fresh install.
- `install.ps1` must stay pure ASCII (no BOM) or PowerShell 5.1 misreads it (`install.ps1:11`).
- CLAUDE.md idempotency relies on the literal string `BEGIN ENGRAM` — don't rename the marker
  without updating both installers.
- `.gitattributes` union-merge only covers journal `*.md` and metrics `*.jsonl` (+ archives);
  other memory files can still merge-conflict.
- Modules must be self-describing (conventions live in copied files, not tooling); core
  tooling may be module-aware but must no-op when the module dir is absent.

## Interfaces
**Depends on:** [[engram-memory-format]], [[engram-hooks]], [[engram-mem-skills]]
**Used by:** [[bug-sweep-module]]
