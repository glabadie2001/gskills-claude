# Engram modules

Engram's core stays lean: index, atlas, architecture, journal, decisions,
gotchas, tasks. Anything a project may or may not need — extra memory layers
with their own conventions — ships as an opt-in **module** under this
directory and composes onto an install without touching what's already there.

## Installing a module

```
# fresh install with modules:
./install.sh --target <repo> --modules bug-sweep
powershell -File install.ps1 -Target <repo> -Modules bug-sweep

# add to an EXISTING install (memory otherwise untouched, tooling untouched):
./install.sh --target <repo> --modules bug-sweep
powershell -File install.ps1 -Target <repo> -Modules bug-sweep
```

Module application is additive and idempotent: files are copied only where
missing (a module NEVER clobbers memory — same contract as the core
installer), and index bullets are appended only if absent. Re-running is
always safe.

## Module contract

A module is a directory `modules/<name>/` containing:

- `MODULE.md` — what the module adds, its conventions, and what drives it.
  First paragraph is the one-line description.
- `memory/` — files/directories copied into `.claude/memory/`, never
  clobbering existing paths.
- `MEMORY-snippet.md` — bullets appended to MEMORY.md's "Where everything
  lives" section (inserted before the `Skills:` block; skipped if the first
  bullet's link target is already mentioned).

Modules must be self-describing: their conventions live in the copied files
themselves (STATUS headers, Conventions sections), not in tooling — so a
memory dir remains fully legible without the engine checkout. Core tooling
may be module-AWARE but must degrade to a no-op when the module is absent
(e.g. the linter's `dead-mdlink` check escalates to ERROR only under
`sweeps/`; the viewer renders a Sweeps layer only if the directory exists).

## Available modules

- **bug-sweep** — adversarial review campaign ledger (`sweeps/INDEX.md` +
  `sweeps/artifacts/` archive) and observed bug-class taxonomy
  (`bug-classes.md`). See `bug-sweep/MODULE.md`.
