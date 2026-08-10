---
name: codex-review
description: Run one full adversarial Codex review round end-to-end — generate the round prompt, trigger a headless Codex CLI review, verify every finding against the code, dispatch tiered fix agents for confirmed findings, run the gates, and write the next round's prompt. Use when the user asks for a Codex review round, an adversarial bug-hunt round, or hands over Codex findings to triage and fix.
---

# Codex review round

One invocation = one complete round, no manual shuttling of deliverables:

```
prompt → codex exec (headless) → verify findings → triage → dispatch fixers → gates → distill → close (commit + next-round prompt) → report
```

The user's role is to invoke the skill and read the final report. Do not
pause mid-round to ask whether to proceed — the invocation IS the approval
for the whole loop, including the round-close commit (Step 9). Stop only
for the standing exceptions: destructive actions, pushes (never), or a
working tree full of unrelated uncommitted work you'd be racing against.

## Flags

- `--triage-only` — stop after Step 4: report verdicts, dispatch nothing.
- `--findings <file-or-pasted-text>` — skip Steps 1–3 and ingest existing
  findings (the user already ran Codex themselves). Start at Step 4.
- `--base <ref>` — review base (default: `origin/<default-branch>`).

## Step 0 — Preflight

1. `codex --version` must succeed; a git repo must be identified (the repo
   under review; if ambiguous, the innermost repo containing CWD).
2. Record HEAD SHA, branch, base ref, and `git status`. A dirty tree with
   changes unrelated to this round → stop and ask; Codex reviews the
   working tree and will report half-done work as bugs.
3. Locate the **round ledger**. If the repo has Engram memory with a
   campaign ledger (`.claude/memory/sweeps/INDEX.md` — Engram's bug-sweep
   module; if Engram is present WITHOUT it, mention that
   `install.ps1 -Target <repo> -Modules bug-sweep` adds it), that is the ledger:
   read its top table for the last round's number, brief/prompt, and
   findings (archived under `sweeps/artifacts/`; full prompts from before
   brief-based archiving live compressed under `sweeps/artifacts/cold/`). Otherwise fall back to loose files
   matching `Codex_Prompt_*Round<N>*.md` in CWD, the repo root, and the
   repo's parent directory — the ledger dir is wherever they already live.
   Either way, the CURRENT round's prompt is STAGED outside the repo (the
   repo's parent directory, falling back to `<repo>/codex-reviews/`) so the
   review never reads its own instructions; it is archived only after the
   round completes.

## Step 1 — Round prompt

If a staged prompt (or brief) for the current round exists but was never
run, use it as-is. Otherwise build the prompt per
`references/round-prompt-template.md`, which has two modes:

**With Engram's bug-sweep module** (the ledger from Step 0 is
`sweeps/INDEX.md`) — the prompt is ASSEMBLED at run time; never carry a
previous prompt forward (copy-forward is what makes prompts and their
archives grow monotonically). Write only the round **brief**
(`Codex_Brief_<M-D-YY>_Round<N+1>.md`) — header + target-diff description +
where-to-hunt — then assemble, in template section order:

- **Ground already covered**: DERIVE from the INDEX rows (round → classes →
  fix commits, one line per distilled round) plus a fuller block for the
  last round from git log / journal. Never stored in the prompt's own
  lineage — the INDEX is the source of truth.
- **Deliberate designs — do not report as bugs**: include
  `sweeps/deliberate-designs.md` VERBATIM. This is what keeps signal high;
  a stale or missing entry costs a round of refuted findings.
- **Where to hunt** (from the brief): re-aim at under-reviewed surfaces.
  The newest fix diff is ALWAYS target #1 — the newest code is the
  least-reviewed code. Draw the rest from `bug-classes.md` OPEN classes'
  hunt heuristics (cite class ids); skip classes marked CLOSED.

**Without the module** (loose-files fallback) — generate
`Codex_Prompt_<M-D-YY>_Round<N+1>.md` from the previous round's prompt,
appending to its Ground-covered and Deliberate-designs sections and
compacting older entries as they age (the template's legacy mode).

## Step 2 — Trigger Codex (headless)

```
codex exec --sandbox read-only -C <repo> --color never \
  -o <ledger-dir>/Codex_Findings_<date>_Round<N>.md - < <prompt-file>
```

- Prompt via **stdin** (`-` + redirect), never argv — avoids all quoting.
- `--sandbox read-only` is non-negotiable: the reviewer must not mutate the
  tree it reviews (no formatter, no fixes).
- Model/effort come from `~/.codex/config.toml`; don't override with `-c`
  unless the user asked.
- Run it as a background shell task and continue only when it completes —
  reviews take 10–45 min. Do not poll; do not fabricate results.
- Non-zero exit or an empty `-o` file → report the failure and stop.

## Step 3 — Receive results

Read the findings file. Expect the output contract from the prompt template
(numbered findings, severity, file:line citations, failure scenario, fix
direction). If Codex declared merge blockers, say so in the report header.

## Step 4 — Verify every finding (the keystone)

**Never fix from the report alone.** For each finding, read the cited code
and re-derive the mechanism yourself; the verdict is yours, not Codex's:

- **CONFIRMED** — mechanism and failure scenario check out (note anything
  the finding understated; verified scope may be broader).
- **REFUTED** — cite the code that disproves it; it goes in
  `sweeps/deliberate-designs.md` (or, without the module, the next round's
  deliberate-designs section) so it is never re-reported.
- **DOWNGRADED / DEFERRED** — real but with a narrower window, an existing
  human checkpoint, or a fix that is feature-scale (schema, contract, UX
  redesign) rather than a bug fix.

≤6 findings: verify inline. More: fan out read-only Explore agents (tiered
and labeled per the model-dispatch rules).

**Interplay check** — for every CONFIRMED finding, ask: does the obvious
fix interact with a deliberate design or a recent fix? (Canonical case: a
"don't replay side effects on retry" fix that would silently break a
retained-key recovery path that DEPENDS on replay re-deriving its work.)
Write the interplay into the fixer's spec as an explicit invariant plus a
scenario table covering both failure modes.

## Step 5 — Triage

- **Fix now**: confirmed correctness, data-integrity, duplicate-side-effect,
  security, and concurrency findings with a contained blast radius.
- **Defer**: schema/contract redesigns, feature-level work, cosmetic/UX
  polish → record in the project task ledger AND the deliberate-designs
  ledger's deferred section (`sweeps/deliberate-designs.md`; without the
  module, the next round prompt's deferred section).

## Step 6 — Dispatch fixers

Follow the model-dispatch rules (explicit `model:` tier on every dispatch,
tier stated with one-line justification, `[Tier]`-prefixed description).
Review-specific requirements for each fixer spec:

- Exact files, exact names, the scenario table from Step 4, the test files
  to extend, and the verification commands to run.
- Disjoint file ownership across parallel fixers; sequence or merge agents
  that would share a file.
- Standing prohibitions in every prompt: no `git stash/reset/checkout`, no
  dev servers, no commits.

## Step 7 — Independent gates

Run the project's gates YOURSELF after the fixers report (discover from
AGENTS.md / CLAUDE.md / package.json — typically fmt + lint + typecheck +
both test suites). An agent's own summary is not verification. A fixer
failing gates twice → escalate one tier with the failure evidence.

## Step 8 — Distill into the taxonomy

Applies when the repo has Engram's bug-sweep module (`bug-classes.md` +
`sweeps/INDEX.md`); otherwise skip to Step 9. This step is what keeps the
taxonomy the campaign's knowledge layer and the ledger a ledger — skip it
and verdict cells silently grow into a shadow taxonomy the graph drowns in.

1. `bug-classes.md` carries a **`Distilled through: round <N>`** marker near
   the top. Every round after the marker is the distillation backlog: the
   round just closed, plus any earlier rounds that closed without this step
   (their INDEX rows and journal entries hold the material — catch them up
   now, in the same pass).
2. For every CONFIRMED finding in the backlog: file a new class (one-sentence
   mechanism + hunt heuristic) or add an instance line to the existing class
   it belongs to; wikilink the atlas card it bites. A round that closes a
   class's last known instance — with a sweep finding no more — marks the
   class **CLOSED** (kept, not deleted: closed classes still teach design
   review, and a reopened one is a signal).
3. **Excise the before/after** — for every confirmed finding, cut the
   minimal bugged snippet and its fixed replacement out of the fix commit
   (`git show <sha>` — trim each side to the lines that carry the
   mechanism, not the whole hunk) into the class's examples file,
   `sweeps/examples/<class-id>-<slug>.md`: one file per class, one
   `## R<N>#<f> — <file:line> (<sha>)` section per instance holding the
   bugged fence, the fixed fence, and a one-line "why the left one is
   wrong". Link the section from the class's instance entry. These pairs
   are the corpus that makes log-dropping lossless — and double as ad-hoc
   post-training examples of this codebase's own blind spots.
4. Compact each distilled round's INDEX verdict cell to counts + class ids
   + a one-line blocker note. This is safe precisely because of steps 2–3:
   the mechanism prose lives in the taxonomy, the code pair in examples/,
   the narrative in the journal; the row keeps its links untouched.
5. **Reconcile `sweeps/deliberate-designs.md`**: this round's refuted and
   deferred verdicts are already filed there (Steps 4–5) — now PRUNE any
   entry this round's fixes invalidated (the design it defends no longer
   exists). A stale entry is worse than a missing one: it is assembled
   into every future prompt and suppresses real findings.
6. Advance the marker. The round is not distilled until the marker names it.

## Step 9 — Close the loop

1. Journal the round if the project has persistent memory (e.g. Engram
   `/mem-journal`); add deferred items to its task ledger.
2. If the repo has an Engram campaign ledger (`.claude/memory/sweeps/`):
   copy the round's BRIEF + findings into `sweeps/artifacts/` (the
   assembled full prompt is never archived — its ledger sections live in
   the INDEX and `deliberate-designs.md`; discard it once the round
   closes), and append the round's row to `sweeps/INDEX.md` with RELATIVE
   markdown links to both artifacts and the journal day (an unlinked
   filename is a broken hierarchy).
3. **Commit the round** — one commit covering the fixes, their tests, and
   any git-tracked ledger/memory updates; message shaped
   `Codex R<N>: <one-line outcome>`. This commit is part of the loop (the
   invocation authorizes it): it is what lets the next round's prompt seed
   "Ground already covered" from `git log` and the INDEX row carry its fix
   sha immediately — fill the sha into the row now, not "once the user
   commits". Stage ONLY files this round touched (preflight already
   screened unrelated work). NEVER push.
4. Write the NEXT round's brief (or, without the module, prompt file) per
   Step 1's rules — the round is not closed until the next one is aimed.
   Seed "Where to hunt" from the just-refreshed taxonomy (Step 8), newest
   fix diff still target #1. It stays STAGED outside the repo until run
   (never pre-archive an un-run brief; assembly happens at run time, so
   the ledger sections it picks up are current by construction).
5. Report to the user, leading with the outcome: a findings table
   (# → severity → verdict → action → status), gate results, files changed,
   deferred list, the round's commit sha, and the path of the next-round
   prompt.
