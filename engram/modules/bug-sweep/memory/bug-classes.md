# Bug-class taxonomy

> **STATUS: EMPTY — no review campaign has exposed classes yet.** The first
> adversarial round replaces this notice with a one-liner (campaign + date
> range) and files its confirmed findings as classes below.

Every bug class the adversarial review campaign exposed in THIS codebase,
with hunt heuristics. These are OUR observed blind spots, not hypothetical
ones. The campaign ledger (every round/sweep → prompts, findings, fix
commits) lives in [INDEX](sweeps/INDEX.md).

Use it three ways: (1) seed class-directed sweep agents, (2) paste relevant
classes into review prompts ("where to hunt"), (3) check new code against it
at design time. Add classes as new rounds find them; mark fixed instances so
sweeps hunt for OTHER instances, not the known ones.

## Format

One `##` family per letter, one bullet per class:

```markdown
## A. <Family name — e.g. Staleness & identity races>

- **A1 <slug>** — one-sentence mechanism. Instances: <round#finding / commit
  sha per instance; mark fixed ones>. Hunt: <greppable patterns, code shapes,
  and angles that find MORE instances of this class>.
```

Keep each class to one bullet; a class that outgrows its bullet is two
classes. Traps discovered while fixing (a pattern that LOOKS like the fix
but is vacuous) go inline as `TRAP:` inside the class.

Linking rules:

- **Wikilink the atlas card(s) where the class bites** — once per class, at
  first confident mention (`…in [[example-module]]'s token broker`). The
  card's backlinks panel then answers "which classes bite this module?".
  Skip modules you can't map to a card with confidence — a wrong link
  asserts a wrong home.
- **Deep-link a family from elsewhere by heading anchor** — ledger rows and
  round prompts can cite `[B4](bug-classes.md#b-family-name)`; classes get
  addressable without splitting this file.
- A cross-cutting trap that is also a class instance stays in `gotchas.md`
  and cites the class id in its text.
- **Do not split this file per class.** Classes are consumed together
  (pasted into prompts, greped as one surface); per-class files atomize the
  taxonomy without adding graph information. If the file outgrows its grain
  (≈250 lines, or one family alone passes ~60), split BY FAMILY into
  `bug-classes/<letter>-<slug>.md` with this file as the index — the mirror
  of the atlas `INDEX-<area>` pattern.

## Classes

*(empty — first confirmed finding starts family A)*
