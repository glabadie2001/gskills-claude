---
module: engram-lint-ci
paths:
  - engram/template/scripts/**
  - engram/template/ci/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Deterministic, zero-token static checks over `.claude/memory` (broken links, stale cards,
budget overruns, dead paths), runnable locally or in CI via a copy-in Actions template.

## Key files
- `engram/template/scripts/engram-lint.sh` — bash 3.2 twin; canonical check order (source of truth when twins disagree)
- `engram/template/scripts/engram-lint.ps1` — PowerShell 5.1 twin; must reproduce findings byte-for-byte
- `engram/template/ci/engram-check.yml` — copy-in workflow: runs the bash linter, posts a Step Summary + card-coverage report, never comments on PRs

## How it works
Both scripts walk memory in a FIXED numbered order (no-git → version-drift → index budget →
per-card checks → INDEX budgets → broken-wikilink → unsigned journal entries →
architecture.md → dead-mdlink) and emit `LEVEL check file message` tuples — the order is the
contract between the twins. Exit 1 iff any ERROR; `--json` emits one stable-schema object.
Per card: frontmatter parsed without a YAML lib, then brace-glob, dead-glob, bad-verified,
staleness, frontmatter-comment, 60-line budget, dead Key-files checks. architecture.md's
Live diagram reuses the card contract (Target exempt by design). The CI card-coverage step
re-implements the frontmatter parse independently in awk/sed.

## Invariants & gotchas
- The twins must stay byte-identical in findings for identical inputs — every edit to one
  requires the mirrored edit; asserted by convention only, no automated cross-check exists.
- engram-check.yml is a MANUAL copy-in: the installers ship `template/scripts` (since
  2026-08-11, tooling section 4) but never `template/ci` — deliberate, since CI needs
  `.claude/scripts` and memory committed; the install summary prints the copy-in hint.
- CI assumes the linter at `.claude/scripts/engram-lint.sh` and needs `fetch-depth: 0` —
  a shallow checkout silently breaks staleness and coverage.
- version-drift reads "Current tooling version" from `mem-sync/MIGRATIONS.md` (currently 8)
  vs `.claude/memory/VERSION`; missing MIGRATIONS.md = INFO skip, not failure.
- Root resolution (since 2026-08-11, v8): missing `<root>/.claude/memory/MEMORY.md` →
  `.claude/engram-root` pin, then one-level probe (sorted, first match), then the existing
  no-memory finding — so linting from a satellite parent hits the child. `-Root`/`--root`
  still overrides the starting point.
- dead-mdlink escalates to ERROR under `sweeps/` (campaign hierarchy), WARN elsewhere;
  `sweeps/artifacts/` is skipped as frozen history.

## Interfaces
**Depends on:** [[engram-memory-format]], [[engram-mem-skills]]
**Used by:** [[bug-sweep-module]]
