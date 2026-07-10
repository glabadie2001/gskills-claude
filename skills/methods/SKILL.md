---
name: methods
description: Catalog of engineering-method playbooks (ratchet-refactor, plan premortem, incident postmortem, schema-recon). Load when starting a large refactor/migration, when a plan is approved but not yet executed, after an incident or escaped defect, or when onboarding an unfamiliar third-party schema/API — pick from the catalog, then read ONLY the matching reference.
---

# Engineering methods

This file is the CHOOSER. Each method has a detailed reference in
`references/<name>.md` — procedure, output contracts, and failure modes.
Pick below, then READ the matching reference before starting:

- `references/ratchet-refactor.md` · `references/premortem.md`
- `references/postmortem.md` · `references/schema-recon.md`

These are *procedures* (how to run a kind of work), where the `orchestration`
skill's topologies are *structures* (how to shape multi-agent dispatch). They
compose: a method names the topology for each of its stages.

## The methods

### 1. Ratchet refactor
Large refactor/migration driven by a countable violation metric: baseline the
count, forbid increases, sweep to zero in waves, keep the gate forever.
- **Fits:** decoupling efforts, deprecation sweeps, style/idiom migrations,
  "no new X" campaigns — anything where the debt is enumerable and the work
  spans many sessions. Not for one-shot refactors that fit a single PR.
- **Signature move:** the metric must be mechanically countable (grep/AST),
  never judgment-based, or the ratchet cannot be enforced.

### 2. Plan premortem
An approved plan, before execution: assume it shipped and failed, enumerate
the failure stories across fixed lenses, and disposition every one (change
plan / add guard / add test / accept with reason) before any code is written.
- **Fits:** plans touching state, money, mail, auth, tenancy, migrations, or
  anything hard to reverse. Skip for trivial reversible changes — the method
  costs one pass and must stay cheap enough to actually run.
- **Signature move:** fixed lenses (idempotency, partial failure, races,
  tenancy, irreversibility), not open-ended "what could go wrong" vibes.

### 3. Incident postmortem
After a production incident or verified escaped defect: timeline → proximate
vs root cause → the missing invariant → three MANDATORY outputs (regression
test, durable guardrail, sibling sweep).
- **Fits:** anything that reached users or survived review+tests. The method
  is the outputs — a postmortem that produces only narrative changed nothing.
- **Signature move:** every postmortem feeds a lens or guardrail back into
  premortem/ratchet, so the same failure class is caught upstream next time.

### 4. Schema recon
Onboarding an unfamiliar third-party system (ERP database, vendor API):
inventory → docs pass (Context7) → triangulated semantic verification →
trap ledger with evidence queries → separate write-path recon.
- **Fits:** any new integration surface where code will depend on field
  semantics you didn't design. Not for schemas you own.
- **Signature move:** docs and names produce *hypotheses*; only probes
  against the live instance produce *facts* — and falsified assumptions
  (misleading names) are recorded as first-class findings.

## Cross-links (don't duplicate these here)

- **Executor specs** — the spec-writing template lives in
  `../orchestration/references/contractor.md` §"Writing the spec". It applies
  to ANY dispatch, not just contractor runs.
- **Premortem-as-dispatch** — the adversarial critic framing ("default to
  refuted") is `../orchestration/references/adversarial.md`.
- **Sibling sweeps / debt discovery** — unknown-size discovery is
  `../orchestration/references/loop-until-dry.md`.

## Choosing

1. Multi-session refactor with enumerable debt? → **1 (ratchet)**.
2. Plan approved, execution not started, failure would be expensive?
   → **2 (premortem)**, then execute.
3. Something already broke in prod (or escaped review)? → **3 (postmortem)**,
   and let its outputs harden 1 and 2.
4. About to integrate against a schema/API you didn't design? →
   **4 (schema-recon)**, before the first line of integration code.
5. Compose: a ratchet's sweep waves are contractor dispatches; a premortem
   can be run as an adversarial dispatch; a postmortem's sibling sweep is a
   loop-until-dry; a recon's trap ledger feeds premortem's wrong-assumption
   lens.
