# bug-sweep — adversarial review campaign ledger + bug-class taxonomy

Memory layers for running a sustained adversarial review campaign against a
codebase: external reviewer rounds (e.g. headless Codex CLI), class-directed
workflow sweeps, and architecture reviews — with every prompt, findings file,
verdict, and fix commit traceable years later.

## What it adds to `.claude/memory/`

- `sweeps/INDEX.md` — the campaign ledger and sole entry point: one row per
  round/sweep/review, linking prompt + findings artifacts, verdicts, fix
  commits, and the journal day. Conventions (artifact naming, the
  stage-outside-then-archive rule, linking style) live in the file itself.
- `sweeps/artifacts/` — the canonical durable archive for prompts, findings,
  sweep scripts, and result JSONs. Matters most when `.claude/` is
  gitignored: this archive is then the only thing that survives a cleanup.
- `sweeps/examples/` — excised before/after code pairs, one file per bug
  class, one section per confirmed instance (minimal bugged snippet + fixed
  snippet from the fix commit + one-line why). Makes compacting
  ledger/journal prose lossless and accumulates a post-training corpus of
  the codebase's observed blind spots.
- `bug-classes.md` — the taxonomy of bug classes the campaign has exposed in
  THIS codebase, with hunt heuristics; seeds review prompts and
  class-directed sweeps. Linking rules (wikilink the atlas card a class
  bites; split by family only when outgrown; never per class) live in the
  file.

Plus two bullets in MEMORY.md's "Where everything lives" (via
`MEMORY-snippet.md`).

## What drives it

- The `/codex-review` skill (user-level, `skills/codex-review/` in this
  repo) runs a full reviewer round end-to-end and closes the loop into this
  module's ledger when present. Its round-close includes the **distill
  step**: confirmed findings roll into `bug-classes.md` (a `Distilled
  through: round N` marker tracks the backlog and forces catch-up), each
  finding's bugged/fixed snippets are excised into `sweeps/examples/`, the
  distilled rounds' INDEX verdict cells compact to counts + class ids, and
  the round is committed so the next prompt seeds "Ground already covered"
  from `git log` and "Where to hunt" from the refreshed taxonomy.
- Workflow class sweeps archive their scripts + results into `artifacts/`
  per the INDEX conventions.

## Core tooling that is module-aware (no-op without it)

- Linter: `dead-mdlink` escalates to ERROR under `sweeps/` (an unlinked
  artifact breaks the campaign hierarchy) and skips `sweeps/artifacts/`
  (frozen history).
- Viewer: renders a dedicated Sweeps graph layer/section; indexes
  `.txt/.js/.json` artifacts under `sweeps/` so non-markdown artifacts are
  graph nodes too.
- `/mem-recall` searches these layers when present.
