# Gotchas

<!-- Cross-cutting traps that bite. Module-specific gotchas belong in that module's
     atlas card instead — put them here only when they span modules or have no card.
     Format: dated bullet, what bites, where, and the rule to follow. Newest first. -->

<!-- Example:
- **2026-01-01** — `npm test` silently skips suites whose filename has a space; CI
  uses a different glob and runs them. Rule: no spaces in test filenames. (found via
  `[[ci]]`, journal 2026-01-01)
-->

- **2026-08-10** — `engram-lint.sh` is unusably slow under Git Bash on Windows (>2 min on
  this repo's small memory — process spawn per checked line); the `.ps1` twin finishes in
  seconds. Rule: on Windows run `engram-lint.ps1` locally; the bash twin is for CI/Linux.
  (found dogfooding, journal 2026-08-10; see [[engram-lint-ci]])
