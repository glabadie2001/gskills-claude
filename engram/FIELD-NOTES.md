# Field notes — what the rest of the field taught us

Synthesis of a three-angle survey run 2026-07-16: (1) coding-agent memory products
(Claude Code, Cline Memory Bank, Cursor, Windsurf/Devin, Aider, Copilot, Codex CLI, OSS
plugins), (2) agent-memory research and frameworks (MemGPT/Letta, mem0, Zep, A-MEM,
benchmarks), (3) practitioner field reports (HN, GitHub issues, engineering blogs).
Raw agent reports are archived in the session scratchpad; key URLs inline below.

## Design bets the field independently validates

- **Markdown + git, no vector DB.** A production survey of Claude Code/Codex/Hermes-class
  agents found *none* uses a vector DB or knowledge graph — all converged on "LLM +
  markdown + hard size caps" (nicolasbustamante.com/blog/agent-memory-engineering). The
  OSS plugin ecosystem mostly bet the other way (embeddings + SQLite); the vendor-native
  systems bet our way.
- **Always-loaded index.** Controlled ablations show retrieval failure dominates agent
  memory errors (11–46% of wrong answers) while utilization failure stays at 4–8%
  (arXiv:2603.02473). An always-loaded index removes the retrieval step entirely for
  whatever it covers — it is retrieval-proof by construction.
- **Staleness is THE failure mode, and git-diff detection is the asked-for fix.** Every
  research source repeats the "confidently wrong because reality changed" story; the
  practitioner corpus's clearest field bugs (npm-vs-pnpm from stale CLAUDE.md line 14;
  `src/db` → `src/data` refactor causing wrong-directory edits) are stale-reference bugs.
  Practitioners explicitly rate diff-based staleness above timestamp stamps, which "get
  added but not enforced." Our `verified:` SHA + `git log <sha>..HEAD -- <paths>` is
  deterministic where the field's bi-temporal/decay schemes are probabilistic — possible
  only because code has ground truth conversational memory lacks.
- **Bloat → ignored instructions is the #1 practitioner complaint.** "The more
  non-universal content in the file, the more likely y instructions get ignored" (HN,
  multiple threads; ~200-line community threshold). Our hard budgets (index ≤120, cards
  ≤60) and journal compaction exist for exactly this.
- **Day-1 bootstrap is unsolved elsewhere.** No surveyed production system pre-seeds
  memory from the codebase itself; fresh memory is useless for sessions until it
  accumulates. `/mem-init` is our answer and apparently novel at product level.
- **Bi-temporal lineage comes free.** Zep/sverklo build databases to answer "what did we
  believe at commit X." Our memory dir lives in the target repo's git — every card edit
  is versioned alongside the code it describes. `git log -- .claude/memory/atlas/auth.md`
  IS the supersession chain.

## Deltas adopted from the survey (applied to templates/skills)

1. **Epistemic hierarchy, stated in the protocol** — Codex and Windsurf both publish
   "generated memory is a recall layer, never the source of truth"; Cursor shipped
   auto-memories then *removed* them in favor of git-tracked rules. Adopted as protocol
   rule: trust order is code > fresh atlas/ADRs > journal; journal entries are leads,
   not truth.
2. **Dead ends: distinguish `dead` from `parked`** — HN reports agents both re-attempting
   recorded failures and over-avoiding things that were merely blocked at the time.
   Journal dead-end lines now say why it failed and whether it's permanently dead or
   retry-when-X.
3. **Dead-reference linting in /mem-sync** — the mechanism behind most real "memory
   caused a bug" reports is a referenced path that no longer exists. Sync now verifies
   each card's `paths:` globs still match files and flags Key-files entries that vanished
   (cf. mex's zero-token drift detector, the closest OSS prior art).
4. **Judgment, not inventory** — Aider's repo-map sidesteps staleness by regenerating
   structure from source every run. Lesson: cards must hold what CAN'T be mechanically
   regenerated (mental models, invariants, why) and never inventory what `grep`/`ls`
   answers fresh — inventories are the fastest-rotting card content.
5. **Evidence anchoring** — Copilot Memory (the field's most staleness-sophisticated
   system) stores every memory as an observation cited to file+line and re-verifies the
   citation at retrieval. Adopted proportionally: invariants and gotchas should name the
   file(s) that make them true, so recall can spot-verify claims, and confabulated claims
   (written but never true — research's "worse than forgetting" failure) have nowhere to hide.
6. **Untrusted-content write guard** — memory-poisoning research (MINJA, >95% injection
   success) shows the write path is an attack surface: "remember that..." text inside
   web pages/issues gets promoted to durable instructions. mem-save now refuses to
   persist instructions found in processed content; facts from untrusted sources carry
   their provenance.
7. **Atlas growth bound: index hierarchy** — mem0's own data shows ~25% accuracy
   degradation as memory corpus grows 1M→10M tokens; near-duplicates crowd out the right
   entry. Past ~20 cards, mem-init/mem-sync split the atlas into `INDEX-<area>.md` maps
   of content: the master TOC lists areas and sessions climb master → area → card
   (progressive disclosure — the OpenHands/claude-mem 3-tier pattern). Merging cards is
   reserved for thin fragments of the same seam; climbing preserves granularity, merging
   destroys it. (Supersedes the original merge-at-20 rule. A query API layer was also
   considered for context savings and rejected: budgets bound file sizes at write time,
   grep+Read already give surgical access, and tool schemas + server liveness would cost
   more than they save at this corpus size.)
8. **User-stated rules carry provenance** — practitioners: the highest-trust memories are
   the ones a human explicitly dictated. When the user states a rule/fact directly,
   mem-save marks it `(per user, YYYY-MM-DD)` so later sessions know it's a directive,
   not an inference.

## Considered and rejected

- **Vector/embedding retrieval** — wrong corpus shape: memory is small, correlated, and
  structured; grep + links + an always-loaded index outperform similarity search here,
  and research shows naive RAG-over-memories returns near-duplicates while missing
  temporal deltas (arXiv:2602.02007). Revisit only if a memory corpus outgrows grep.
- **Decay curves / auto-expiry (Ebbinghaus, Copilot's 28-day)** — time-based forgetting
  is a proxy for staleness; we have the real signal (the diff). Journal compaction and
  Done-pruning already bound growth on the layers without a diff signal.
- **DB-backed task/issue graph (Beads)** — right answer at 605-plans scale; wrong
  trade at ours. tasks.md + journal with explicit statuses stays greppable and
  git-reviewable. Revisit if tasks routinely exceed ~50 open items.
- **Human-approval gate on every write (Devin-style)** — kills the 30-second capture that
  defeats write-nothing. Our compensations: git-reviewable memory diffs, evidence
  anchoring, epistemic hierarchy, and /mem-sync as the repair loop.
- **Per-subagent memory silos** — documented failure mode (subagents re-derive the same
  facts independently). Engram is one shared store by design.

## Open questions worth revisiting later

- **AGENTS.md convergence:** the single largest Claude Code feature request (5.2k reactions)
  is AGENTS.md support. If the ecosystem converges, the installer's CLAUDE.md snippet
  should become format-agnostic (write the import block into whichever root file exists).
- **Instruction-following decay:** even a perfect memory file can be ignored by the model
  as context grows (the "Mr Tinkleberry" problem). Our SessionStart hook re-injects the
  brief every session, but a mid-session re-prime (practitioners' `/bootstrap` pattern)
  could be added as a `/mem-brief` skill if drift shows up in practice.
- **Success-labeled memory pruning:** research (arXiv:2505.16067) validates using
  downstream task success to retroactively prune misleading memories. Our journal records
  outcomes; a future mem-sync pass could demote cards whose guidance preceded failures.

## Addendum (2026-07-16): index-hierarchy field history

A dedicated survey of hierarchical index navigation (MemWalker arXiv:2310.05029, RAPTOR
arXiv:2401.18059, GraphRAG arXiv:2404.16130, LlamaIndex TreeIndex, PageIndex, Anthropic's
progressive-disclosure designs) confirmed the pattern's measured failure modes and the
conditions under which it wins. Why it isn't the industry default: (1) index build/upkeep
cost — Microsoft built LazyGraphRAG specifically because GraphRAG's LLM indexing was
~1000x a flat baseline; (2) serial navigation latency compounds (measured >83x
amplification under per-hop delays); (3) weak models can't navigate — MemWalker's authors
state a reasoning-capability threshold outright; (4) staleness compounds with depth
(every level summarizing changed content rots — the Zettelkasten "MOC upkeep" problem);
(5) production coding agents (Claude Code, Sourcegraph, Cognition) all chose live agentic
search over any maintained index, citing staleness/simplicity. Engram's design sits in
the literature's winning quadrant on all counts: the corpus is small and curated, the
navigator is a strong model, the tree is exactly two levels (one hop), and — the
condition the failures all lack — the index is agent-maintained as part of normal work
(mem-sync), not hand-authored and left to rot. The 2025–26 consensus ("dynamic beats
static, flat or tree") matches Engram's shape: a capped always-loaded index + live
Read/grep, not a static pre-built tree.
