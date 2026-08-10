---
module: example-module
paths:
  - src/example/**
  - lib/shared/example.ts
verified: 0000000
verified_date: 2026-01-01
verified_by: claude-model-id (effort)
---

<!-- Frontmatter contract — parsed by scripts; keep it EXACTLY this shape:
     module: kebab-case, must match the filename (example-module.md).
     paths: block-style list of globs defining this module's code footprint; they drive
       staleness detection via `git log <verified>..HEAD -- <paths>`. Globs must be
       git-pathspec compatible: NO brace expansion like src/{a,b}/** (git matches nothing,
       silently breaking staleness — use two entries instead). Verify each glob matches
       files: `git ls-files '<glob>'` must produce NON-EMPTY output.
     verified: short git SHA of a COMMIT the body was last checked against.
     verified_by: exact model id (+ effort if known) of the model that actually read the
       code for this verification, e.g. claude-sonnet-5 or claude-fable-5 (xhigh) —
       updated together with verified/verified_date, never separately. A card verified by
       a smaller model at low effort deserves proportionally more spot-checking.
     NO inline # comments inside the frontmatter — parsers treat them as glob text. -->

# example-module

**Purpose:** What this module exists to do, in at most two lines.

## Key files

- `src/example/index.ts` — public entry point; exports X and Y
- `src/example/core.ts` — the actual algorithm
- `src/example/adapters/` — one adapter per backend

## How it works

The mental model in ≤15 lines. Data flow, lifecycle, the one diagram-in-words a new
session needs to modify this code without rereading all of it. Prefer "A calls B which
persists to C" over prose about philosophy.

## Invariants & gotchas

- INVARIANT: things that must stay true, anchored to the file that makes them true
  (e.g. "every adapter is stateless — instances are shared across requests (`src/example/core.ts`)")
- GOTCHA (2026-01-01): things that bite, with date and file ref

## Interfaces

- **Depends on:** [[other-module]], external service Z
- **Used by:** [[api]], [[cli]]

<!-- Budget: ≤60 lines. Edit in place — never append contradictions. After any edit
     that re-verifies claims against code, bump `verified` to the current HEAD sha
     (git rev-parse --short HEAD) and `verified_date` to today.
     Cards hold JUDGMENT — mental models, invariants, why — never inventories of what
     grep/ls can regenerate fresh (function lists, file trees): those rot fastest and
     the code answers them better. -->
