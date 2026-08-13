# 001 — Replace lone SHA-range freshness with manifest-based dual-axis trust

- **Date:** 2026-08-12
- **Status:** accepted (implementation deferred to phase plan below; not yet started)
- **By:** claude-fable-5

## Decision

Atlas-card freshness becomes two axes: computed `current` (per-file footprint manifest
set-compare, never a writable field) × sync-owned `attested` (the existing verification
act, SHA triple retained). Per-task card updates earn scoped, evidence-preserving credit
via manifest lines for the session's own committed files only, under a pre-image rule.
Rollout is phased: read side first, write path gated on demonstrated detector yield.

## Context

Comparing Engram to Xirp's "living documentation" surfaced a wish: cards refreshed after
every task, not only at /mem-sync. The naive patch — mem-journal bumps `verified` to
HEAD per task, dropping the already-stale exception — was adversarially reviewed by a
3-lens Fable panel and **refuted 3–0**: staleness is computed solely as
`git log <verified>..HEAD -- <paths>` (brief, linter, sync all share it), so one
optimistic bump permanently destroys the only evidence; claim-checking cannot see
omissions (cards are judgment, not inventory); stamps made pre-commit vouch for code the
SHA doesn't contain; author self-stamping collapses the journal/atlas trust order; and
no toothy intra-day-staleness harm could even be constructed — the "gap" was the honest
signal working. A 4-angle judge-panel brainstorm (~30 mechanisms) then converged
unprompted on the manifest + dual-axis composite; the same three critics gave final
**signoff-with-conditions** (all conditions folded into the spec below).

## Spec (as signed off)

1. **Footprint manifest.** Git-tracked sidecar per card: every tracked file under the
   card's globs + blob hash (from `git ls-files -s`). Freshness = set-compare: per-file
   CHANGED / ADDED (under globs, absent from manifest — deterministic file-granular
   omission detector) / REMOVED, plus DIRTY via `git diff --name-only` + untracked
   check. Dirty detection stays on git's side of the CRLF filter boundary. Manifests
   are **script-generated only** (linter recomputes and ERRORs on mismatch) and
   **commit-gated** — never written against a dirty tree; DIRTY is a designed,
   lint-clean state shown as one aggregate brief line.
2. **Dual axis.** `current` = manifest match — computed, linter ERROR if it appears in
   frontmatter. `attested` = verification act; `verified`/`verified_date`/`verified_by`
   stay (manifest refines the range check, never replaces it). States: VERIFIED /
   DRIFTED / ASSUMED / ABANDONED. mem-init writes new cards ASSUMED (fixes the
   unearned-✓-at-birth bug — mem-init currently stamps `verified: HEAD` on cards never
   verified against anything). Protocol rule 1: "trust it" maps to VERIFIED only;
   DRIFTED = trust minus the enumerated delta files.
3. **Pre-image rule (the load-bearing amendment; demanded independently by all three
   critics).** A per-task manifest-line update for file F is legal only if F's line
   matched F's blob before this session's edit; otherwise leave the line — sync owns
   it. VERIFIED additionally requires every commit in `attested..HEAD -- <globs>` to
   have co-modified the manifest legally; merges never do → post-merge cards are
   DRIFTED until sync (closes take-both merge minting).
4. **Guards.** `paths:` edits outside a verification act drop `attested` (scope-shrunk
   lint). Card-body commits postdating the attestation display DRIFTED-amended, never
   bare VERIFIED. `revoked:` is a metadata-only frontmatter line keyed to the
   attestation SHA (no new file; no replacement-claim text — the card body remains the
   single home for the correction); drops the card to map-only until a later
   attestation clears it. `architecture.md` derives state from member cards (no
   union-glob manifest). Statusline cache gains an index-mtime key. Viewer joins the
   rollout.
5. **Migration.** Backfill each manifest from `git ls-tree -r <verified> -- <paths>` —
   states exactly what was actually verified; no unearned trust minted. MIGRATIONS hop
   + template + three installs (incl. satellite).
6. **Phasing (blocking).** Phase 1 = read side: manifest generator twins, brief
   set-compare, ASSUMED labeling, backfill, mem-init fix. Phase 2 (per-task manifest
   write path in mem-journal 3.2, `revoked:` plumbing) waits until one sync cycle shows
   the detector catching something `verified..HEAD` missed — scorecard usage evidence
   is currently too thin to justify the write-side complexity upfront.

## Alternatives rejected

- **Per-task `verified` bump (drop the already-stale exception)** — refuted 3–0; see
  Context. The "conservatism" is the load-bearing wall.
- **Post-session transcript distillation (Xirp-style flow-back)** — collides with
  curated one-home-per-fact design; noise Engram can't absorb.
- **Heavy tamper machinery** (hash-chained attestation ledgers, per-commit disposition
  receipts, challenge sampling) — passes gates, fails adoption: the documented field
  failure is skills not firing; ceremony raises skip rate.
- **Usage-derived trust** (survival credit, witness quorums) — fed by events.jsonl,
  which demonstrably goes silent (9 sessions / 0 events on 2026-08-11); "read and
  didn't complain" is the weakest epistemic step in the pool.
- **Pure TTL / churn-mass heuristics** — trade loud false positives for quiet false
  negatives; acceptable as adjuncts, not as the backbone.

## Consequences

Cheaper session-start freshness (~3 process spawns vs ~30). Uncommitted work,
file-granular omissions, and laundering become visible; a wrong stamp becomes a
detectable lint ERROR instead of a permanent silent blind spot. The user's per-task
living-documentation cadence becomes the credited path (card + manifest + code in one
commit). Costs: manifest sidecars need a merge driver + `-diff` attribute; four states
are harder to render honestly than one binary; mem-journal 3.2, protocol rules 1/5,
DESIGN.md, and all tooling twins must move together in one migration.
