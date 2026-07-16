<!-- Journal file format — one file per day: journal/YYYY-MM-DD.md
     Entries are APPEND-ONLY, newest at the bottom. Written by /mem-journal
     (or directly, following this exact shape). Keep entries ≤12 lines.
     Signature: every headline ends with [<exact model id> · <effort>], e.g.
     [claude-fable-5 · xhigh] — the model that did the work; omit "· effort" if unknown. -->

# Journal — YYYY-MM-DD

## HH:MM — One-line headline of what happened [claude-model-id · effort]

- **Did:** what was accomplished, concretely
- **Learned:** non-obvious facts discovered (omit if none)
- **Dead ends:** what was tried and FAILED, and why — the highest-value line in this file.
  Mark each `dead:` (don't retry — reason is permanent) or `parked:` (retry when X changes) (omit if none)
- **Touched:** files changed
- **Next:** follow-ups filed to tasks.md, atlas cards updated, e.g. [[example-module]] (omit if none)
