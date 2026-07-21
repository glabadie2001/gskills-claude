# Bug Sweep & Review Index

> **STATUS: EMPTY — no adversarial review campaign has run yet.** The first
> review round or class sweep replaces this notice with a one-liner naming the
> campaign (reviewer tool, start date) and appends its row below.

Master ledger of the adversarial review campaign: every external-reviewer
round (e.g. headless Codex CLI), class-directed workflow sweep, and
architecture review — prompt/findings artifacts, verdicts, and fix commits —
so any flaw can be traced across the whole campaign to its fix. This file is
the sole entry point; children are reached from here, not browsed.

## Conventions

- **`artifacts/` is the canonical durable archive.** Round prompts are STAGED
  outside the repo while a round runs (a working-tree review must never read
  its own instructions — and if `.claude/` is gitignored, nothing outside this
  archive survives a cleanup). Copy a round's prompt+findings into
  `artifacts/` and link them in its row only AFTER the round completes.
  Workflow sweep scripts + result JSONs are archived the same way (their
  session/temp homes get cleaned).
- **Naming:** `<Reviewer>_Prompt_<M-D-YY>_Round<N>.md`,
  `<Reviewer>_Findings_<M-D-YY>_Round<N>.md`; sweep scripts keep their
  workflow id (`<name>-wf_<id>.js`) beside `<name>-results.json`.
- **Linking:** artifacts and journal days use RELATIVE markdown links
  (`[findings](artifacts/…)`, `[../journal/YYYY-MM-DD.md](…)`) — the viewer
  renders these as graph edges; `[[wikilinks]]` stay reserved for atlas
  cards. An unlinked filename is a broken hierarchy.
- **Classes:** findings cite ids from the [bug-classes](../bug-classes.md)
  taxonomy; add new classes there as rounds expose them.
- No line budget: this ledger is append-only, one row per round/sweep.

## Reviewer rounds

| Round | Date | Prompt | Findings | Verdicts | Fix commits | Journal |
|---|---|---|---|---|---|---|
| *(empty — first round appends here)* | | | | | | |

## Class sweeps (workflow pyramids, adversarial refuters)

| Sweep | Date | Script | Results | Verdicts | Fix commits | Journal |
|---|---|---|---|---|---|---|
| *(empty)* | | | | | | |

## Architecture reviews

| Review | Date | Prompt | Findings | Outcome | Journal |
|---|---|---|---|---|---|
| *(empty)* | | | | | |

## How to use this index

- **Trace a flaw across the campaign:** find its class in
  [bug-classes](../bug-classes.md), then follow the findings links above for
  the class id or file name; the fix-commit column gives `git show` targets.
- **Before a new sweep:** read the last sweep's script for the finder/refuter
  prompt shapes and coverage conventions; read the latest round prompt for
  the deliberate-designs ledger.
- **After any sweep/round:** copy the artifacts into `artifacts/` first, then
  append the row here WITH links, and record the fix commit sha once the
  user commits.
