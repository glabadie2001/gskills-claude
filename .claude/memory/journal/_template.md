<!-- Journal file format — one file per day: journal/YYYY-MM-DD.md
     Entries are APPEND-ONLY, newest at the bottom. Written by /mem-journal
     (or directly, following this exact shape). Keep entries ≤12 lines.
     Signature: every headline ends with [<exact model id> · <effort>], e.g.
     [claude-fable-5 · xhigh] — the model that did the work; omit "· effort" if unknown.
     Wikilinks: link the PRIMARY module(s) the entry is about — once, at first mention,
     in whichever line names them. Not every occurrence, not incidental modules: a link
     asserts "an atlas card holds the current truth on this."
     Commits: when a milestone ends in a commit, journal AFTER committing so the sha
     exists; never invent or guess shas. -->

# Journal — YYYY-MM-DD

## HH:MM — One-line headline of what happened [claude-model-id · effort]

- **Did:** what was accomplished, concretely — wikilink the primary module(s) once, e.g. fixed refresh race in [[example-module]]
- **Learned:** non-obvious facts discovered (omit if none)
- **Dead ends:** what was tried and FAILED, and why — the highest-value line in this file.
  Mark each `dead:` (don't retry — reason is permanent) or `parked:` (retry when X changes) (omit if none)
- **Touched:** files changed
- **Commits:** short shas this work produced, e.g. abc123f, def456a (omit if nothing committed yet — never invent)
- **Next:** follow-ups filed to tasks.md, atlas cards updated (omit if none)
