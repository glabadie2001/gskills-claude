# Model dispatch

**HARD GUARD — every Agent/Workflow dispatch, read-only fan-outs included:** always pass an explicit `model:` (or `agent(…, {model})` in workflows). Omitting it inherits the session model, so a top-tier session bills every subagent at top-tier rates.

- Prefix each direct Agent `description` with its tier: `[Opus] Logout audit`, `[Haiku] Rename config keys`. Workflow stages declare tiers in `meta.phases` instead.
- State the tier and a one-line reason to the user before dispatching.
- Quick rubric: **Haiku** = mechanical, fails loudly · **Sonnet** = well-specified multi-file work in existing idioms · **Opus** = subtle-failure work (concurrency, migrations, middleware, security) · **inline** = high-risk AND under-specified.
- Pick agent type by least privilege: `Explore` for read-only search, `Plan` for design, `general-purpose` only when it must write.
- Before any multi-agent dispatch or Workflow, load the `orchestration` skill and read `references/model-tiers.md` (full rubric, Fable rules, orchestrator duties, stage tiering) plus the topology reference.
