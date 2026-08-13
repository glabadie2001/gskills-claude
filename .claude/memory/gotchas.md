# Gotchas

<!-- Cross-cutting traps that bite. Module-specific gotchas belong in that module's
     atlas card instead — put them here only when they span modules or have no card.
     Format: dated bullet, what bites, where, and the rule to follow. Newest first. -->

<!-- Example:
- **2026-01-01** — `npm test` silently skips suites whose filename has a space; CI
  uses a different glob and runs them. Rule: no spaces in test filenames. (found via
  `[[ci]]`, journal 2026-01-01)
-->

- **2026-08-11** — A session launched from a PARENT dir of an Engram-fied repo silently
  disables everything anchored to the project root: Claude Code never honors a subdir's
  `settings.json` hooks, and the skills' guard ("no `.claude/memory/` here") beats any
  CLAUDE.md prose telling the model to redirect (proved by a day of genius-sync sessions
  logging zero recall events). Rule: never rely on CLAUDE.md prose for redirection — use
  the v8 pin/probe resolution (`.claude/engram-root` + one-level probe) and the installer's
  satellite mode for parent workspaces. (journal 2026-08-11; [[engram-installer]], [[engram-hooks]])
- **2026-08-11** — Git Bash process spawns cost ~1s EACH on this machine (measured: 10
  trivial spawns ≈ 10s wall, near-zero user/sys — likely AV hooking process creation; git
  config tuning is irrelevant). Consequences: `engram-lint.sh` >2 min, statusline bash twin
  ~4 min (killed by Claude Code → stale renders), brief hook blew its 30s timeout (briefs
  silently dropped). Rule: everything Claude Code invokes must run the `.ps1` twin on
  Windows — statusline via install-time registration, brief/capture via `$OSTYPE` exec
  dispatch in the `.sh`, linter run directly (`engram-lint.ps1`; bash twin is for CI/Linux).
  (journals 2026-08-10/11; see [[engram-hooks]], [[engram-lint-ci]])
