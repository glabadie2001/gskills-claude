---
module: claude-config-mirror
paths:
  - README.md
  - rules/**
  - agents/**
  - CLAUDE.md
  - .gitignore
  - .gitattributes
verified: cd47bba
verified_date: 2026-08-10
verified_by: claude-fable-5
---
The repo's reason for being: a version-controlled mirror of `~/.claude` customizations
(rules, agents, skills) that syncs across machines and installs by copy or symlink.

## Key files
- `README.md` — contents map, install-by-copy/symlink instructions, update workflow
- `CLAUDE.md` — repo-root project file; just the Engram memory import block
- `rules/model-dispatch.md` — global rule: decide model tier + agent type before any dispatch; workflow tiering; orchestration topology chooser
- `rules/context7.md` — global rule (`alwaysApply: true`): Context7 MCP for library docs
- `agents/architect.md` — opus, read+report-only whole-codebase audit agent
- `agents/Explore.md` — sonnet, read-only fan-out search agent
- `.gitignore` — machine-local secrets/state, in case the mirror grows to match a real install
- `.gitattributes` — LF normalization + `merge=union` for Engram's append-only journal/metrics files

## How it works
Repo layout mirrors `~/.claude/` 1:1: `rules/`, `agents/`, `skills/` map onto the real
install dirs. Nothing here is executed in-repo — files are copied or symlinked into
`~/.claude/`; symlinking makes `git pull` update the live install. Rules auto-load every
session across all projects; agents become invocable subagent types.
`model-dispatch.md` tells Claude to load the `orchestration` skill before designing
multi-agent work, so [[skill-catalogs]] must be installed alongside it.

## Invariants & gotchas
- Directory names must stay 1:1 with `~/.claude/` subfolders — the README install commands
  assume the structure; renaming breaks them.
- The two agents are read-only by design (no Write/Edit in `tools:` frontmatter); preserve
  the least-privilege split when adding agents (the model-dispatch rule depends on it).
- `.gitattributes` union-merge rules are tied to Engram's specific append-only paths;
  a new append-only Engram file type needs a matching entry or same-day edits conflict.
- `skills/methods` cross-links into `skills/orchestration/references/` — both must be
  installed together or links dangle.

## Interfaces
**Depends on:** [[skill-catalogs]]
**Used by:** none — this is the outermost layer
