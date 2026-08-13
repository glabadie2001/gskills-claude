
<!-- BEGIN ENGRAM (installed by the Engram memory engine — satellite) -->
## Project memory (Engram — satellite of `{{CHILD}}`)

This directory is a **satellite**: it carries Engram tooling (skills, hooks, lint) but no
memory of its own. The persistent memory lives at `{{CHILD}}/.claude/memory/`, pinned in
`.claude/engram-root`.

Treat `{{CHILD}}/` as the repo root for all memory work: run git as `git -C {{CHILD}} …`
when stamping card freshness, resolving SHAs, or reading history, and write every atlas
card, journal entry, decision, task and metric under `{{CHILD}}/.claude/memory/`. Never
create a `.claude/memory/` here.

The index below is always loaded; follow its Protocol section — read the atlas before
exploring code, journal at milestones, keep one home per fact.

Questions about `{{CHILD}}` whose answer lives in a memory layer — "how does X work"
(atlas), "why is it like this" (decisions), "what was tried, what dead-ended" (journal),
"what bites here" (gotchas) — are answered by invoking the `/mem-recall` skill, not by
re-exploring code. Questions a live query answers authoritatively — git state ("did we
push X?"), current file contents, test results — go straight to that tool, with no
recall event: git answers whether/when, memory answers why and what-it-was-like.

@{{CHILD}}/.claude/memory/MEMORY.md
<!-- END ENGRAM -->
