# Tasks

<!-- Living task ledger. Now = actively being worked. Next = queued. Later = someday.
     Done items move to Done (recent) with a date; /mem-sync prunes Done items older
     than 14 days (the journal keeps the story). One line per task; link context with
     `[[atlas-card]]` or journal dates. -->

## Now

## Next

- Installer never copies `template/scripts/` (linter) or `template/ci/` — fresh installs
  have zero linting until someone copies them by hand; wire into install.ps1/sh
  (found by mem-init exploration, see [[engram-lint-ci]])
- bug-sweep: extend the v6 cold-store pattern to FINDINGS of distilled rounds (prompts
  already got it) — user-requested 2026-08-10, see [[bug-sweep-module]]

## Later

- Hub-and-spoke memory reconciliation (multi-user Engram) — concept + tax recorded in
  `engram/CONCEPTS.md`; cheap first slice is the `branch:` card frontmatter field with
  linter awareness
- Team hardening for pure-git memory: atlas merge driver (keep both bodies, zero
  `verified`), MEMORY.md regenerate-on-conflict, tasks dedupe at sync, optional
  `linguist-generated` collapse for PR views (see `engram/CONCEPTS.md`)
- Viewer: metrics scorecard/trend panel from `metrics/events.jsonl`

## Done (recent)
