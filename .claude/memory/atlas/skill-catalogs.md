---
module: skill-catalogs
paths:
  - skills/methods/**
  - skills/orchestration/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
Two chooser-style skill catalogs that steer multi-agent work: orchestration picks the
topology (shape/tiering), methods picks the engineering procedure (what to do).

## Key files
- `skills/orchestration/SKILL.md` — chooser: 7 topologies + the "where does an uncaught error become irrecoverable" decision rule
- `skills/orchestration/references/` — one file per topology (pyramid, contractor, judge-panel, adversarial, escalation-ladder, loop-until-dry): stage table, tiers, skeleton, failure modes
- `skills/methods/SKILL.md` — chooser: 4 engineering methods (ratchet-refactor, premortem, postmortem, schema-recon)
- `skills/methods/references/` — one file per method: procedure, output contract, failure modes
- `skills/orchestration/references/contractor.md` — holds the executor-spec template (its "Writing the spec" section), cross-linked (not duplicated) by methods

## How it works
Both share a chooser pattern: a thin SKILL.md decision tree routes to exactly ONE
`references/<name>.md`, loaded on demand — never load all references. Orchestration answers
"how to shape a dispatch" (pyramid=facts/audits, contractor=implementation,
judge-panel=design choices, adversarial=verify-the-verifier, escalation-ladder=unknown
difficulty, loop-until-dry=unbounded discovery). Methods answers "what procedure to run" —
each method's stages NAME an orchestration topology rather than reinventing dispatch
mechanics, and methods cross-links into orchestration's references (spec template,
adversarial critic framing) instead of duplicating.

## Invariants & gotchas
- Install both directories together — methods cross-links `../orchestration/references/*`
  by relative path; one without the other leaves dangling links.
- SKILL.md must stay a thin chooser; detail belongs only in `references/<name>.md` — this
  is what keeps skill-loading cheap.
- Orchestration's tier guidance ("fan-out cheap, verify/synthesize smart") is the mechanism
  `rules/model-dispatch.md` depends on — keep topology tiers consistent with that rule.
- contractor.md's "Writing the spec" section is the single source of truth for executor
  specs; methods reference it, never fork a second copy.

## Interfaces
**Depends on:** none — leaf catalogs, pure playbooks
**Used by:** [[claude-config-mirror]], [[codex-review]]
