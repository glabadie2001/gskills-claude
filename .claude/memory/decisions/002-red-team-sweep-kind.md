# 002 — Make red-team review a first-class sweep KIND, not a new module

- **Date:** 2026-08-13
- **Status:** accepted (spec below; promotion to the engine template GATED on round 2)
- **By:** claude-opus-5

## Decision

A red-team (adversary-model security) review is a distinct **class of insight** from a
correctness bug round, and gets first-class support inside the existing `bug-sweep`
module via a `sweep-kind` axis — NOT a forked `red-team` module. The class adds three
memory shapes bug-sweep has no analog for: a threat-model registry, a model-scoped risk
ledger, and a verified-clean surface ledger whose staleness is computed by the v9
manifest machinery. Promotion into `engram/modules/bug-sweep/` waits until a second
red-team round exercises the shapes live in genius-sync.

## Context

genius-sync ran its first red-team review 2026-08-13 (LAN + agentless-tunnel exposure,
confidential BOM data; 11 findings). Writing it into the bug-sweep ledger, the session
independently invented a `<!-- sweep-kind: red-team -->` marker (repeated as the
artifact's first line so tooling can classify from either side), a separate INDEX
section, a "never fold its counts into correctness verdict totals / never feed its
confirmed count to the clean-round loop" rule, and a "read the prior report's *What
held* first" usage note. A convention inventing itself under pressure is the signal that
the class is real; the question is what makes it a class rather than a row type.

Three properties distinguish a red-team finding from a bug finding:

1. **The truth-condition is a threat model, not the code.** A bug is true or false
   against the source. Finding F2 (`X-Tenant` is trusted for any registered tenant, RBAC
   is global) is *working exactly as written* — it is a finding only under the
   confidential-BOM adversary model. Ranking basis is attacker value, not defect
   severity. Without a stated model, "is this a finding?" is unanswerable, and each
   round re-derives the frame from scratch (round 1 spent its whole opening section
   doing exactly that).
2. **Closure is a risk decision, not a fix commit.** bug-sweep's terminal state is a fix
   SHA. Red-team findings terminate in accept / mitigate / defer-by-date, owned by a
   person — and acceptance is **model-scoped**. This is the load-bearing trap:
   `deliberate-designs.md` is assembled VERBATIM into every round prompt, so filing "F2
   accepted" there unqualified would permanently suppress it, including under a future
   model where cross-company confidentiality does matter. A not-bug is universal; an
   accepted risk is conditional.
3. **"What held" is an asset with a shelf life.** The report's verified-clean section
   (genuine JWKS validation on both runtimes, ORDER BY whitelist holds, all 13 Next
   mini-db routes RBAC+tenant gated) is *coverage*, not absence — and it is exactly the
   shape of an atlas-card claim: true at SHA X for paths Y. That is what
   [[adr-001|decisions/001]]'s manifests already compute, which is the strongest reason
   to make this an Engram class instead of prose in one install's INDEX.

## Spec

1. **`sweep-kind` becomes module contract.** Machine-readable `<!-- sweep-kind: <id> -->`
   immediately above each non-Codex section's table in `sweeps/INDEX.md`, repeated as
   the FIRST line of the corresponding artifact. Linter (module-aware, no-op without
   `sweeps/`): marker required on both sides, and a mismatch between an artifact's
   marker and its linking section's is an ERROR. Ids are open; `red-team` is the first.
2. **Tally isolation.** Rows of a non-default kind are excluded from correctness verdict
   totals and never feed the clean-round loop. A red-team row routinely contains items
   that are working as written; folding them in corrupts the campaign's defect signal in
   both directions.
3. **`sweeps/threat-models.md`.** Named models — adversary, assets, boundary, what the
   perimeter does and does not buy. Every red-team finding cites one. Assembled into
   red-team round prompts the way `deliberate-designs.md` is assembled into correctness
   prompts. Models are versioned by addition, never edited silently: a widened model is
   a new entry, because it reopens previously accepted risks.
4. **Model-scoped risk ledger.** Accepted/deferred red-team verdicts do NOT go into
   `deliberate-designs.md` unqualified. Each carries `model:` (which threat model it was
   ruled under), `accepted-by`, and `revisit-when`. A risk accepted under model M is
   silent only for rounds run under M or narrower.
5. **`sweeps/verified-clean/` with manifest freshness.** Each cleared surface is a small
   file carrying `paths:` globs + a `verified:` SHA — deliberately the same frontmatter
   shape as an atlas card, so `engram-manifest` stamps and set-compares it with the
   existing code path generalized from `atlas/` to a list of claim directories. The next
   round's brief then states which cleared surfaces have DRIFTED (re-check these) and
   which are VERIFIED (do not re-derive these). This is the phase-2 write-path question
   from ADR 001 in a second setting; it must not fork a parallel manifest implementation.

## Phasing (blocking)

This class has run exactly once. Following ADR 001's precedent — phase 2 gated on
demonstrated detector yield — the engine template changes wait until a **second**
red-team round in genius-sync exercises `threat-models.md` and the risk-ledger fields
live, and shows that either (a) the prior round's "What held" was re-derived without it,
or (b) a model-scoped acceptance would have been wrongly suppressed. Until then the
convention stays live-only in genius-sync, where it is already self-describing.

## Alternatives rejected

- **A separate `red-team` module** — forks `artifacts/`, the INDEX-as-sole-entry-point
  invariant, fix-commit traceability, and `examples/`, all of which red-team rounds
  genuinely share. Two ledgers means neither is the entry point, and cross-kind tracing
  ("did the fix for F1 come from the security round or round 33?") stops working.
- **Just a row in the existing table, no marker** — the ranking basis differs, so the
  verdict column stops meaning one thing; the clean-round loop silently ingests
  working-as-written items as defects.
- **Folding accepted risks into `deliberate-designs.md` as-is** — universal suppression
  of a conditional verdict; the file is injected verbatim into every prompt, so the
  error is invisible and permanent.
- **A `security` atlas card instead** — cards describe what code IS; this is campaign
  state (rounds, verdicts, coverage-at-a-SHA), which is ledger-shaped.

## Consequences

Security coverage gains a shelf life: cleared surfaces expire against code drift instead
of aging into implied safety, reusing machinery that already shipped. Risk decisions
become auditable — who accepted what, under which adversary model, revisitable by date.
Costs: the manifest tooling must generalize past `atlas/` (a second consumer is the test
of whether ADR 001's design was actually a general claim-freshness mechanism or an
atlas-only one); the linter grows kind-marker checks; `bug-sweep` outgrows its name once
it hosts more than one kind, and renaming a shipped module is a migration.
