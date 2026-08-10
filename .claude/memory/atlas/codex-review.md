---
module: codex-review
paths:
  - skills/codex-review/**
verified: b1de8e9
verified_date: 2026-08-10
verified_by: claude-sonnet-5
---
User-level skill that runs one complete adversarial Codex-CLI review round end-to-end —
prompt assembly, headless review, verification, tiered fixes, gates, distillation — in one loop.

## Key files
- `skills/codex-review/SKILL.md` — the 9-step round protocol (preflight → prompt → codex exec → verify → triage → dispatch → gates → distill → close)
- `skills/codex-review/references/round-prompt-template.md` — the two prompt-build modes and the exact section order the parser depends on

## How it works
One invocation = the whole loop; the invocation is the approval, including the round-close
commit — only destructive actions or unrelated dirty-tree work stop it. Assembled mode
(bug-sweep module present): only a round BRIEF is written and archived; the full prompt is
reassembled fresh each round from INDEX-derived ground-covered + deliberate-designs verbatim
+ template, then discarded — this is what stops prompts growing monotonically. Legacy mode
(no module): the previous full prompt is carried forward. Step 4 (verify) is the keystone:
every finding is re-derived from actual code — CONFIRMED / REFUTED / DOWNGRADED-DEFERRED —
plus an interplay check against deliberate designs and recent fixes. Step 8 (distill,
module-only) rolls confirmed findings into the taxonomy, excises before/after pairs into
`sweeps/examples/`, prunes stale deliberate-designs entries, advances `Distilled through`.

## Invariants & gotchas
- `codex exec` must run `--sandbox read-only` with the prompt via stdin, never argv — the
  reviewer must never mutate the tree it reviews.
- The round's own prompt/brief is staged OUTSIDE the repo so the review never reads its
  own instructions.
- The assembled full prompt is never archived — a stale deliberate-designs entry is worse
  than a missing one (injected into every future prompt, suppressing real findings).
- A dirty tree with unrelated changes stops preflight — Codex reports half-done work as bugs.
- A round isn't closed until the next round's brief is staged, and isn't distilled until
  the `Distilled through` marker advances.

## Interfaces
**Depends on:** [[bug-sweep-module]], [[skill-catalogs]]
**Used by:** [[bug-sweep-module]]
