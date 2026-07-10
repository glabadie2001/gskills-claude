# Schema recon

Onboarding an unfamiliar third-party system — an ERP database, a vendor API,
a SaaS surface — far enough to integrate against it safely. The core
principle: **names and docs generate hypotheses; only probes against the
live instance produce facts.** Column names lie ("Complet" that isn't a
completion flag), fields get repurposed by customizations ("Description3"
packing two values), and views silently filter rows. Every load-bearing
claim gets verified empirically before code depends on it.

## Stage design

| Stage | Who | Notes |
|---|---|---|
| Inventory | cheap fan-out (haiku/sonnet) or plain SQL | enumerate tables/endpoints, row counts, populated vs empty, module presence |
| Docs pass | inline, via Context7 / vendor docs | produces HYPOTHESES, labeled as such — never facts |
| Semantic verification | inline or opus — the smart stage | one triangulated probe per load-bearing field; wrong-but-plausible here is the disaster |
| Trap ledger | inline, continuous | verified facts AND falsified assumptions, each with its evidence query |
| Write-path recon | separate pass, always | read semantics ≠ write semantics; find the sanctioned write surface |

## Procedure

1. **Inventory before interpretation.** List what exists and what's actually
   populated: row counts per table, which modules/endpoints are present,
   which are installed-but-empty. "Empty now" is a fact worth recording —
   but it means *this instance doesn't use it*, not *it's safe to ignore
   forever*.
2. **Docs pass, via Context7 where the vendor is covered.** Follow the
   context7 rule (resolve-library-id → query-docs) for APIs/SDKs; fall back
   to vendor PDFs and existing mapping artifacts for proprietary ERPs.
   Record what the docs CLAIM each field means — then treat every claim as
   a hypothesis. Docs describe the vendor's intent for some version; the
   customer's instance has customizations, version drift, and years of
   field misuse the docs can't know about.
3. **Verify semantics by triangulation, never by name.** For each field the
   integration will depend on, confirm meaning at least two independent
   ways: find a known transaction in the vendor's own UI and check the raw
   value matches; write a probe that PREDICTS a value from the hypothesis
   and run it; cross-foot an aggregate against a screen total. One
   triangulated example beats ten documented claims. A field nobody
   verified is a hypothesis, whatever the mapping doc says.
4. **Falsified assumptions are first-class findings.** "X does NOT mean
   what its name says, evidence: <query>, <date>" prevents every future
   session (and every dispatched agent) from re-deriving the trap. The
   misleading-name entries end up more valuable than the confirmations.
5. **Classify views vs base tables early.** Derived views join, filter, and
   drop rows without saying so. For every view, answer: what does it
   exclude relative to its base tables, and is it writable? Do arithmetic
   (sums, fulfillment math) against base tables unless the view's filter is
   verified to be what you want.
6. **Recon the write path separately.** The table you read is often not the
   surface you write (read-only join views with a separate write entity;
   server-derived columns that reject client values; fields where the
   vendor is source-of-truth and overriding causes errors). Never infer
   write behavior from read behavior — find the sanctioned write API and
   probe it against a disposable record.
7. **The ledger is the deliverable.** A mapping doc checked into the repo,
   one row per field: claimed meaning (docs), verified meaning, status
   (`verified` / `hypothesis` / `falsified`), and the evidence query with
   date. Statusless mapping docs rot into folklore; the status column is
   what lets a later reader know which rows to trust.

## Orchestration pairing

- Inventory is pyramid-shaped: mechanical, parallel, cheap
  (`../../orchestration/references/pyramid.md`).
- Semantic verification is where plausible-but-wrong survives — run it
  smart, or adversarially for the highest-stakes fields
  (`../../orchestration/references/adversarial.md`).
- "Find every place that reads field X" during later integration is
  `../../orchestration/references/loop-until-dry.md`.

## Failure modes

- **Trusting names** — the field named for a concept doesn't hold it;
  the classic entry in every trap ledger.
- **Trusting docs over the instance** — vendor docs describe intent for
  some version; the installed, customized instance is the ground truth.
- **Single-sample verification** — one row where the hypothesis holds
  proves little; blanks, nulls, and legacy rows are common. Probe across
  statuses and eras of data.
- **Arithmetic against a filtered view** — totals silently exclude rows
  (unposted, inactive, soft-deleted) and the numbers are wrong forever.
- **Write-by-analogy** — inferring the write path from read structures;
  probe writes explicitly, on disposable data.
- **Ledger without evidence** — conclusions recorded without the query
  that proved them can't be re-verified after an upgrade, and get
  re-litigated every time they look surprising.
