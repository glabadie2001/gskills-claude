# Round-prompt template

Two modes. **Assembled mode** applies when the repo has Engram's bug-sweep
module (`sweeps/INDEX.md` + `sweeps/deliberate-designs.md`): the archived
artifact is the round BRIEF; the full prompt is assembled fresh every
round and discarded at round close. **Legacy mode** (no module) carries
the previous prompt forward. Either way the assembled/final prompt keeps
the section order below, and the Method/Output sections near-verbatim —
Codex's output contract is what Step 3 parses.

## Assembled mode

The brief, `Codex_Brief_<M-D-YY>_Round<N>.md`, holds ONLY the per-round
unique material — everything else is pulled from its canonical home at
assembly time. Never paste ledger content into the brief: if it is worth
keeping, it belongs in the INDEX, `deliberate-designs.md`, or
`bug-classes.md`, where the next assembly picks it up automatically.

```markdown
# Codex round brief — Round <N> (<YYYY-MM-DD>)

<Header: repo, HEAD short-sha, branch, base ref, expected tree state.>

<Target-diff description: what the newest diff(s) under review are —
commit shas, scope (files, +/− lines), the mechanics a reviewer needs to
review them. This is target #1 material and unique to this round.>

## Where to hunt (under-reviewed surfaces)

<Re-aim every round. Rules of thumb:
1. The previous round's fix diff is ALWAYS target #1 — newest code is the
   least-reviewed code. Name the specific files/state machines it touched.
2. Draw surfaces from bug-classes.md OPEN classes' hunt heuristics and
   cite the class ids ("A1 in sibling consumers of X"); skip classes
   marked CLOSED. The taxonomy is refreshed at every round close (SKILL
   Step 8), so it is current by construction.
3. Keep a numbered list of 6–10 concrete surfaces (module + what could be
   wrong there), not vague areas.
4. Rotate in surfaces that have had little adversarial attention; drop
   surfaces that produced nothing two rounds running.>

## Assembly

Assembled <YYYY-MM-DD> with: deliberate-designs.md (<entry count> entries),
ground-covered derived from INDEX rows ≤ R<N-1>.
```

Assemble the full prompt in this order:

1. **Preamble** — from the brief's header, wrapped in the standing frame:
   "Perform an adversarial correctness review of the `<repo>` repository at
   HEAD (`<short-sha>`, branch `<branch>`) against `<base-ref>`. Read-only:
   do NOT edit files or run mutating commands (no formatter, no fixes).
   Goal: find real, demonstrable bugs — correctness, data integrity,
   privacy/tenancy, concurrency, and duplicate-side-effect risks — that
   earlier rounds have not already found." Then the brief's target-diff
   description.
2. **`## Ground already covered (rounds 1–<N-1>) — do not re-tread`** —
   DERIVED from the INDEX: one line per distilled round (round → class ids
   → fix commits, straight from its verdict cell), a fuller block (what was
   fixed, at which commits, with regression tests) for rounds since the
   `Distilled through` marker, from git log / journal.
3. **`## Deliberate designs — do not report as bugs`** —
   `sweeps/deliberate-designs.md` included VERBATIM (drop its STATUS
   notice if still empty).
4. **`## Where to hunt (under-reviewed surfaces)`** — from the brief.
5. **Method requirements + Output format** — verbatim from Legacy mode
   below.

Fill the brief's `## Assembly` line when assembling — it is the manifest
that records what ledger state the round ran against (the ledgers have no
git history when `.claude/` is gitignored).

## Legacy mode (no bug-sweep module)

Generate `Codex_Prompt_<M-D-YY>_Round<N>.md` in the ledger dir by carrying
the previous round's prompt forward and updating the bracketed parts.

```markdown
# Codex bug-search prompt — Round <N> (<YYYY-MM-DD>)

Perform an adversarial correctness review of the `<repo>` repository at
HEAD (`<short-sha>`, branch `<branch>`) against `<base-ref>`. Read-only: do
NOT edit files or run mutating commands (no formatter, no fixes). Goal:
find real, demonstrable bugs — correctness, data integrity,
privacy/tenancy, concurrency, and duplicate-side-effect risks — that
earlier rounds have not already found.

## Ground already covered (rounds 1–<N-1>) — do not re-tread

[Carry the previous round's list forward. Append a new block for round
<N-1>: what was fixed, at which commit(s), with regression tests. Compress
older rounds into one-line summaries as the list grows — the point is
"don't re-report", not history.]

## Deliberate designs — do not report as bugs

[Carry forward. Append, from the round just closed:
- new accepted trade-offs (with the one-line WHY),
- REFUTED findings and the reason they don't hold,
- DEFERRED findings, marked "known, deferred by decision — do not
  re-report; fix tracked in <task ledger>",
- known-pending manual checks (live smokes etc.) marked "pending, not a
  finding".]

## Where to hunt (under-reviewed surfaces)

[Re-aim every round, per the same rules of thumb as Assembled mode —
minus the taxonomy, unless the repo carries a loose `bug-classes.md`.]

## Method requirements

- Verify every candidate finding against the actual code path before
  reporting; include concrete file:line references and a specific
  input/state → wrong-outcome scenario. Findings that don't survive your
  own re-check should be dropped, not hedged.
- Check that formatting CI (`<fmt-check-command>`) passes at HEAD and call
  it out as a merge blocker if not (do not run the mutating formatter).
- Do not propose multi-step fixes; one sentence of fix direction per
  finding is enough.

## Output format

Same structure as previous rounds: a numbered `## Findings` list ordered by
severity (merge blockers first, then medium-high → low), each with severity
label, one-paragraph description with file:line citations, the concrete
failure scenario, and a one-line fix direction. State explicitly if no
merge-blocking bugs were found. Note the reviewed SHA and base at the top.
```
