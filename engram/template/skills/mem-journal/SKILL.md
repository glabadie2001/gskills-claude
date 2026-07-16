---
name: mem-journal
description: Append an entry to Engram project memory's journal for work just done, then reconcile tasks, atlas cards, and gotchas. Use after completing a task, fixing a bug, hitting a dead end, learning something non-obvious, after any substantial multi-file change, when a work session is wrapping up, or when the user says "log this".
when_to_use: Invoke at work milestones, not at session end only — completed a task, fixed a bug, hit a dead end, learned something non-obvious, finished a substantial multi-file change, about to finish a work session, or the user says "log this" / "journal this". Sessions die without warning; deferred capture is capture that never happens.
argument-hint: [optional headline]
---

# /mem-journal — log what just happened

If given, $ARGUMENTS seeds the entry headline.

## 0. Guard

If `.claude/memory/` does not exist in this repo, say "Engram is not installed here (no .claude/memory/)" and stop.

## 1. Resolve date and time

Get today's date (YYYY-MM-DD) and local time (HH:MM) from the shell — use whichever shell is available:

- PowerShell: `Get-Date -Format "yyyy-MM-dd HH:mm"`
- bash/sh: `date "+%Y-%m-%d %H:%M"`

## 2. Append the entry

Open `.claude/memory/journal/YYYY-MM-DD.md`. If it does not exist, create it with this first line exactly:

```markdown
# Journal — YYYY-MM-DD
```

APPEND the entry at the very bottom of the file. Never edit existing entries, never insert above them. Exact entry format — keep the whole entry ≤12 lines; omit any field with nothing to say (do not write "none"):

```markdown
## HH:MM — One-line headline
- **Did:** what was accomplished, concretely
- **Learned:** non-obvious facts discovered (omit if none)
- **Dead ends:** what was tried and FAILED, and why (omit if none)
- **Touched:** files changed
- **Next:** follow-ups filed, cards updated e.g. [[module]] (omit if none)
```

Dead ends are the highest-value field. If anything was tried and abandoned this session, record what and why — this is what saves the next session from repeating it. Mark each one `dead:` (don't retry — the reason is permanent) or `parked:` (worth retrying when X changes); an unmarked failure gets both wrongly retried and wrongly avoided by later sessions.

## 3. Reconcile the other layers

Do every step that applies, now, in the same turn:

1. **tasks.md** — move tasks this work finished from `## Now`/`## Next` to `## Done (recent)`, appending today's date to the line as `(YYYY-MM-DD)` — /mem-sync parses exactly that format when pruning. Add newly discovered follow-ups as one-liners under `## Next`.
2. **Atlas cards** — if the work invalidated a claim in any `.claude/memory/atlas/<module>.md` card, fix that card body now. Then: after editing an atlas card, bump `verified` to `git rev-parse --short HEAD` and `verified_date` to today ONLY IF (a) you actually checked the card's claims against current code during this work, AND (b) the card was not already stale (i.e. `git log --oneline <verified>..HEAD -- <paths>` is empty apart from your own just-made changes). If the card was already stale, edit the body but LEAVE the old sha — /mem-sync owns full re-verification.
3. **gotchas.md** — if a cross-cutting trap was discovered (spans modules, or no card covers it), add a dated bullet at the TOP of the list (newest first): `- **YYYY-MM-DD** — what bites, where, and the rule to follow.` Module-specific traps go in that module's atlas card instead.
4. **Decisions** — if a significant decision was made (real alternatives were weighed, reversal would be costly), OFFER to write an ADR in `decisions/`. Never write an ADR silently — ask the user first.

## 4. Report

Finish with one line: what was journaled and which layers were reconciled.
