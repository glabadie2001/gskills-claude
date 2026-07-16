---
name: codex-review
description: Run one full adversarial Codex review round end-to-end — generate the round prompt, trigger a headless Codex CLI review, verify every finding against the code, dispatch tiered fix agents for confirmed findings, run the gates, and write the next round's prompt. Use when the user asks for a Codex review round, an adversarial bug-hunt round, or hands over Codex findings to triage and fix.
---

# Codex review round

One invocation = one complete round, no manual shuttling of deliverables:

```
prompt → codex exec (headless) → verify findings → triage → dispatch fixers → gates → next-round prompt → report
```

The user's role is to invoke the skill and read the final report. Do not
pause mid-round to ask whether to proceed — the invocation IS the approval
for the whole loop. Stop only for the standing exceptions: destructive
actions, commits (only when the user asked), pushes (never), or a working
tree full of unrelated uncommitted work you'd be racing against.

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
3. Locate the **round ledger**: files matching `Codex_Prompt_*Round<N>*.md`
   in CWD, the repo root, and the repo's parent directory. The ledger dir is
   wherever they already live. Bootstrapping a first round: use the repo's
   PARENT directory (outside the repo, so the review never reads its own
   instructions), falling back to `<repo>/codex-reviews/` if the parent is
   unsuitable.

## Step 1 — Round prompt

If a prompt for the current round exists but was never run, use it as-is.
Otherwise generate `Codex_Prompt_<M-D-YY>_Round<N+1>.md` from the previous
round's prompt using `references/round-prompt-template.md`. The prompt is a
LEDGER, not boilerplate — three sections carry the round-to-round memory:

- **Ground already covered**: append what the last round fixed (from git
  log / project journal), so Codex never re-treads verified territory.
- **Deliberate designs — do not report as bugs**: append any new accepted
  trade-offs, deferred-by-decision items, and known-pending checks from the
  last round. This is what keeps signal high; skimping here costs a round
  of refuted findings.
- **Where to hunt**: re-aim at under-reviewed surfaces. The newest fix diff
  is ALWAYS target #1 — the newest code is the least-reviewed code.

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
- **REFUTED** — cite the code that disproves it; it goes in the next
  round's deliberate-designs section so it is never re-reported.
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
  polish → record in the project task ledger AND the next round prompt's
  deliberate-designs/deferred section.

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

## Step 8 — Close the loop

1. Journal the round if the project has persistent memory (e.g. Engram
   `/mem-journal`); add deferred items to its task ledger.
2. Write the NEXT round's prompt file per Step 1's ledger rules — the round
   is not closed until the next one is aimed.
3. Report to the user, leading with the outcome: a findings table
   (# → severity → verdict → action → status), gate results, files
   changed, deferred list, and the path of the next-round prompt.
4. Do NOT commit unless the user asked; NEVER push.
