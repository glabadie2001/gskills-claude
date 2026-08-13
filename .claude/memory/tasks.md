# Tasks

<!-- Living task ledger. Now = actively being worked. Next = queued. Later = someday.
     Done items move to Done (recent) with a date; /mem-sync prunes Done items older
     than 14 days (the journal keeps the story). One line per task; link context with
     `[[atlas-card]]` or journal dates. -->

## Now

## Next

- Manifest freshness phase 1 (read side): manifest generator twins, brief set-compare,
  ASSUMED labeling, `ls-tree` backfill, mem-init unearned-✓ fix — spec + blocking
  conditions in decisions/001-manifest-freshness.md; user-approved 2026-08-12, start
  next workday. Phase 2 (per-task write path, `revoked:`) gated on detector yield.
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
- Metrics denominator: capture hook (or a SessionEnd sibling) appends a per-session
  event (recall count, atlas reads) so the scorecard can show sessions-vs-recalls —
  a "9 sessions / 0 recalls" day should be visible, not silent (idea from 2026-08-11
  satellite incident; see journal)

## Done (recent)

- Engram v8: nested-root resolution (pin `.claude/engram-root` → one-level probe) across
  hooks/skills/lint + installer `-Satellite` mode; satellite-installed UnifiedServer →
  genius-sync, E2E recall event verified from the parent (2026-08-11)

- Installers now ship `template/scripts/` (lint twins) as tooling section 4; verified via
  -RefreshTooling on this repo (both twins) + linter run. `template/ci/` stays a deliberate
  manual copy-in, now hinted in the install summary (see [[engram-lint-ci]]) (2026-08-11)
