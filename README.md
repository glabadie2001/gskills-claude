# gskills-claude

Personal Claude Code customizations (skills + rules), version-controlled so they
sync across machines. Mirrors the `~/.claude/` layout, so the folders map 1:1
onto a real install.

## Contents

```
rules/
  model-dispatch.md   # global rule: decide model tier + agent type before implementing; workflow tiering
  context7.md         # global rule: use Context7 MCP for library/framework docs
skills/
  orchestration/      # multi-agent topology catalog (pyramid, contractor, judge-panel, …)
    SKILL.md
    references/
  methods/            # engineering-method playbooks (ratchet-refactor, premortem, postmortem)
    SKILL.md          # chooser — routes to references/ without loading them all
    references/
agents/
  architect.md        # Senior Principal Architect — whole-codebase audit → CODE_REVIEW_FINDINGS.md
  Explore.md          # read-only fan-out search agent (returns conclusions, not file dumps)
```

## Install on a machine

Copy (or symlink) each item into `~/.claude/`:

```bash
# from a clone of this repo
cp -r rules/*       ~/.claude/rules/
cp -r skills/*      ~/.claude/skills/
cp -r agents/*      ~/.claude/agents/

# or symlink so `git pull` here updates the live copies:
ln -s "$PWD/rules/model-dispatch.md"  ~/.claude/rules/model-dispatch.md
ln -s "$PWD/rules/context7.md"        ~/.claude/rules/context7.md
ln -s "$PWD/skills/orchestration"     ~/.claude/skills/orchestration
ln -s "$PWD/skills/methods"           ~/.claude/skills/methods
ln -s "$PWD/agents/architect.md"      ~/.claude/agents/architect.md
ln -s "$PWD/agents/Explore.md"        ~/.claude/agents/Explore.md
```

`~/.claude/rules/*.md` auto-loads every session, all projects. Skills load on
demand. After installing, run `/memory` in a session to confirm the rules are
picked up.

## Updating

Edit the file here, `git commit`, `git push`. On another machine, `git pull`
(and re-copy, unless you symlinked).

## Note

`model-dispatch.md` tells Claude to load the `orchestration` skill before
designing any multi-agent dispatch — so keep the two together.

`skills/methods` cross-links into `skills/orchestration/references/` (spec
template, adversarial critic, loop-until-dry) rather than duplicating them —
install both or the links dangle.
