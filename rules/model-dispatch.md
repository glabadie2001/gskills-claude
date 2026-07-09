# Model dispatch: decide the tier before implementing

**HARD GUARD — applies to EVERY Agent/Workflow dispatch, including exploration and read-only fan-outs, not just implementation:** never call the Agent tool without an explicit `model:` parameter (or `agent(…, {model})` in workflows). Omitting it silently inherits the session model — a top-tier session then bills every subagent at top-tier rates. Before any dispatch, state the tier per the rubric below and pass it explicitly. If you catch yourself about to dispatch without a tier decision, stop and make one.

**Label every direct Agent dispatch with its tier:** prefix the `description` with the model in brackets — `[Opus] Logout audit + DB split`, `[Haiku] Rename config keys` — so the tier is visible in the task list, not buried in the call. This applies to direct Agent-tool dispatches only; Workflow stages instead declare tiers in `meta.phases` and per-agent `label`s stay clean.

When it's time to write code (a plan is approved, a spec exists, or the user says "implement"), explicitly decide which model tier executes it — don't default to doing it inline. Subagent-driven development is the default; inline execution by the top model is the exception, reserved for high-risk work.

## Decision rubric

Rate the task on two axes: **spec precision** (is the change fully described — files, names, expected behavior?) and **failure subtlety** (would a wrong implementation fail loudly in tests, or silently in production?).

- **Haiku** — mechanical and loud-failing: renames, config changes, applying a precisely written diff, boilerplate from an exact template, single-file edits with existing tests covering them.
- **Sonnet** — well-specified multi-file implementation that follows existing codebase idioms: CRUD endpoints, UI components matching sibling components, test suites from a described contract, refactors with a clear before/after shape.
- **Opus** — subtle-failure or framework-internals work: decorators/middleware wrapping request lifecycles, concurrency, migrations, introspection/metaprogramming, security-sensitive paths, anything where a plausible-looking implementation can be wrong in ways local tests won't catch.
- **Inline (top model, no dispatch)** — only when the work is high-risk AND under-specified: the spec would take longer to write than the change, correctness depends on judgment calls that can't be delegated, or the change touches auth/data-integrity code where a review pass isn't enough.

## Orchestrator duties (regardless of tier)

1. **Spec quality determines the viable tier.** Read the key files yourself first; a precise spec (exact files, exact names, the idiom to copy, the tests to run) drops the required tier by one level. If you can't write that spec, the tier is higher than you think.
2. **Sequence agents that share files.** Parallel agents editing the same file race; split by file ownership or run sequentially.
3. **Verify independently.** Run the tests/typecheck yourself after the agent reports done; don't accept the agent's summary as verification.
4. **Escalate one tier on failure.** If an agent's output fails verification twice, re-dispatch to the next tier up with the failure evidence in the prompt — don't retry the same tier with the same spec.

State the tier decision and its one-line justification to the user before dispatching.

## Agent picker: type is a separate axis from tier

Every dispatch makes TWO choices: model tier (rubric above) and **agent type** (toolset + system prompt). They compose — Explore-on-haiku is a cheap sweep; general-purpose-on-opus is a subtle executor. A named agent's frontmatter `model` is only its *default*, though — to actually decouple type from tier you must pass an explicit override (Agent tool `model:` param, or `agent(…, {model})` in a workflow); otherwise the agent's pinned model wins. The available roster is session-specific (built-ins + project `.claude/agents/*.md`) — check the session's agent listing before dispatching; a project-defined specialist whose domain matches beats the generic equivalent.

Selection logic (least privilege first):

- **Read-only search / fan-out over code or files** → `Explore`. It returns conclusions, not file dumps, and cannot write — the right shape for pyramid/loop-until-dry probe stages and "where is X" questions. State the breadth ("medium" / "very thorough").
- **Designing an implementation plan** → `Plan` (full read/search, no write) — use before contractor execution when the design isn't decided.
- **Executing changes** → `general-purpose` (full tools; `claude` is the equivalent catch-all). The only types that should ever hold Write/Edit in a dispatch.
- **Whole-codebase architectural audit** → `architect` (read + report, no Write/Edit) — a concrete example of preferring the domain specialist over a generic reviewer.
- **Verification stages** → read-only types (`Explore`, or schema-forced workflow agents) unless the verifier must run tests, in which case general-purpose with the test command specified.
- **In Workflow scripts** → the default workflow subagent is fine for schema-forced stages; pass `agentType` when a stage needs a custom system prompt (it composes with `schema`).

Guard: never hand write-capable agents to stages that only read — least privilege bounds both accidental damage and prompt-drift, and read-only agents are cheaper to permission.

## Choosing an orchestration topology (master rule)

Before designing ANY multi-agent dispatch or Workflow script, load the `orchestration` skill and pick the topology deliberately. The bottom-up pyramid below is ONE topology, not the default for everything. The master question: **where does an uncaught error become irrecoverable? Put the smartest model there; put cheap models wherever errors are caught downstream.** Quick chooser:

- Fits one context, no parallelism win → no orchestration (inline or one agent).
- Unknown difficulty, singular task → escalation ladder (cheap first, one tier up per verified failure).
- Deliverable is a design/choice in a wide solution space → judge panel (STRONG candidates — the pool quality is the ceiling — cheaper judges with a rubric).
- Deliverable is implementation of a decided design → top-down contractor (top model writes specs inline, mid-tier executes, orchestrator verifies).
- Deliverable is facts about a large surface → pyramid (below); swap in loop-until-dry when surface size is unknown; make the verify stage adversarial when plausible-but-wrong is the main risk.

## Workflow orchestration: tier every stage explicitly

In Workflow scripts, `agent()` calls **inherit the session model by default** — an un-tiered workflow run from a top-model session bills every stage at top-model rates. Never leave `model`/`effort` implicit in a workflow; choose per stage.

**Shape rule — wide runs cheap, narrow runs smart.** Fan-out stages (N parallel agents) dominate token spend; the stages that see everything at once are few. Tier down the wide stages and spend the savings on the narrow ones.

Stage-role rubric:

- **Mechanical fan-out** (grep-and-classify, inventories, extraction, format transforms, per-item boilerplate): `haiku` or `sonnet` with `effort: 'low'`. The schema parameter plus a precise prompt substitutes for model intelligence.
- **Investigation** (read a subsystem, index call sites, trace data flow, summarize): `sonnet`. This is the default workhorse tier for anything with a clear question and a bounded search space.
- **Verification / adjudication** (spot-check claims against source, adversarial refutation, judge panels): `opus`, often `effort: 'high'`. Verification is where wrong-but-plausible slips through — don't cheap out here. Exception: majority-vote redundancy (3+ identical verifiers) tolerates `sonnet`, since the vote covers individual weakness.
- **Synthesis / final ruling** the user will act on: the top available model, `effort: 'high'` — exactly one agent, at the end, with authority to re-read disputed code and overrule earlier stages.

Operational rules:

1. **Declare the tier in `meta.phases`** (the `model` field) so the cost shape is visible in the permission dialog before the run starts.
2. **Escalate a stage, not the workflow.** If validators overturn a large share of an investigator stage's claims, re-run that stage one tier up (resume via `resumeFromRunId` so clean stages replay from cache) — don't re-run the whole workflow at a higher tier.
3. **Same failure rule as single dispatch:** two failed verifications of a stage's output → next tier up with the failure evidence in the prompt.
