#!/usr/bin/env python3
"""engram-cost.py -- attribute Claude Code session spend to Engram.

Reads Claude Code transcript files (~/.claude/projects/<project>/*.jsonl, plus any
subagent transcripts under <project>/<session-id>/), reconstructs every API request
from the `usage` blocks, prices it, and splits each session's cost into:

  fixed     the first request's cache WRITE (system prompt + CLAUDE.md + MEMORY.md +
            skill listing + hook output). Paid once per session.
  engram    requests whose assistant turn invoked Engram: a /mem-* skill, a tool call
            touching .claude/memory/, an atlas freshness `git log <sha>..HEAD`, or a
            subagent whose prompt is about atlas cards / memory.
  other     everything else.

Each tool-call round is one API request that re-reads the whole context, so the honest
unit of Engram overhead is "how many extra rounds did it cause", priced at that
session's context size -- which is what this reports.

Usage:
  engram-cost.py                       # sessions of the current project, last 20
  engram-cost.py --project /path/to/repo
  engram-cost.py --transcript a.jsonl  # one file
  engram-cost.py --all                 # every session, not just the last 20
  engram-cost.py --price sonnet-4-6=3,15   # override $/MTok in,out for a model substring
  engram-cost.py --detail <session-prefix>  # per-request breakdown of one session

Pricing is first-party Anthropic list price (cache write 1.25x / 1h 2x, cache read 0.1x).
Bedrock / Vertex / Enterprise contracts differ -- the RATIOS still hold, the dollars are
approximate. Requires python3 only.
"""
import argparse, glob, json, os, re, statistics, sys
from collections import defaultdict

# $/MTok (input, output). Matched by substring against the model id, first hit wins.
PRICES = [
    ("fable",       10.0, 50.0),
    ("mythos",      10.0, 50.0),
    ("opus",         5.0, 25.0),
    ("sonnet-5",     2.0, 10.0),
    ("sonnet-4-6",   3.0, 15.0),
    ("sonnet",       3.0, 15.0),
    ("haiku",        1.0,  5.0),
]
CACHE_READ_MULT = {"fable": 0.025}   # everything else 0.1
DEFAULT_READ_MULT = 0.1
WRITE_5M, WRITE_1H = 1.25, 2.0

ENGRAM_SKILLS = re.compile(r"\bmem-(init|save|arch|journal|recall|sync)\b|\bcodex-review\b")
ENGRAM_PATH = re.compile(r"\.claude[/\\]memory")
FRESHNESS_GIT = re.compile(r"git\s+(-C\s+\S+\s+)?log\s+--oneline\s+[0-9a-f]{7,40}\.\.HEAD")
ENGRAM_AGENT = re.compile(r"atlas card|\.claude/memory|verified:\s*[0-9a-f]{7}|Engram", re.I)


def price_for(model, overrides):
    m = (model or "").lower()
    for sub, i, o in overrides:
        if sub in m:
            return i, o
    for sub, i, o in PRICES:
        if sub in m:
            return i, o
    return None


def read_mult(model):
    m = (model or "").lower()
    for sub, mult in CACHE_READ_MULT.items():
        if sub in m:
            return mult
    return DEFAULT_READ_MULT


def cost_of(u, model, overrides):
    p = price_for(model, overrides)
    if not p:
        return None
    pin, pout = p
    cc = u.get("cache_creation") or {}
    w1h = cc.get("ephemeral_1h_input_tokens") or 0
    w5m = (u.get("cache_creation_input_tokens") or 0) - w1h
    return (
        (u.get("input_tokens") or 0) * pin
        + w5m * pin * WRITE_5M
        + w1h * pin * WRITE_1H
        + (u.get("cache_read_input_tokens") or 0) * pin * read_mult(model)
        + (u.get("output_tokens") or 0) * pout
    ) / 1e6


def project_dir_for(path):
    path = os.path.abspath(path)
    enc = re.sub(r"[^A-Za-z0-9]", "-", path)
    base = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    cand = os.path.join(base, enc)
    if os.path.isdir(cand):
        return cand
    # Loose fallback: same trailing component.
    tail = enc.rstrip("-").split("-")[-1]
    hits = [d for d in glob.glob(os.path.join(base, "*")) if os.path.isdir(d) and d.rstrip("-").endswith(tail)]
    return hits[0] if len(hits) == 1 else None


def iter_lines(fp):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def is_engram_turn(content):
    """content: list of assistant content blocks. True if any tool_use is Engram work."""
    for b in content or []:
        if b.get("type") != "tool_use":
            continue
        name = b.get("name") or ""
        inp = b.get("input") or {}
        blob = json.dumps(inp)
        if name == "Skill" and ENGRAM_SKILLS.search(inp.get("skill", "") or ""):
            return True
        if ENGRAM_SKILLS.search(inp.get("command", "") or "") and name in ("Skill", "Bash"):
            return True
        if ENGRAM_PATH.search(blob):
            return True
        if name == "Bash" and FRESHNESS_GIT.search(inp.get("command", "") or ""):
            return True
        if name in ("Agent", "Task") and ENGRAM_AGENT.search(inp.get("prompt", "") or ""):
            return True
    return False


def load_session(main_file, overrides):
    """Return dict with per-request list for a session (main + subagent transcripts)."""
    sid = os.path.splitext(os.path.basename(main_file))[0]
    files = [main_file]
    side_dir = os.path.join(os.path.dirname(main_file), sid)
    if os.path.isdir(side_dir):
        files += sorted(glob.glob(os.path.join(side_dir, "**", "*.jsonl"), recursive=True))

    reqs = {}          # message id -> record
    order = []
    first_prompt = None
    first_ts = None
    models = defaultdict(int)
    for fp in files:
        sub = fp != main_file
        for o in iter_lines(fp):
            t = o.get("type")
            if t == "user" and first_prompt is None and not o.get("isSidechain"):
                c = o.get("message", {}).get("content")
                if isinstance(c, str):
                    first_prompt = c
                elif isinstance(c, list):
                    for b in c:
                        if b.get("type") == "text":
                            first_prompt = b.get("text"); break
            if t != "assistant":
                continue
            m = o.get("message") or {}
            if m.get("model") in (None, "<synthetic>") or o.get("isApiErrorMessage"):
                continue
            u = m.get("usage") or {}
            mid = m.get("id") or o.get("uuid")
            r = reqs.get(mid)
            if r is None:
                r = {"id": mid, "model": m.get("model"), "usage": u, "content": [],
                     "sub": sub or bool(o.get("isSidechain")), "ts": o.get("timestamp")}
                reqs[mid] = r; order.append(mid)
                if first_ts is None: first_ts = o.get("timestamp")
                models[m.get("model")] += 1
            r["content"].extend(m.get("content") or [])
    recs = []
    for mid in order:
        r = reqs[mid]
        u = r["usage"]
        r["engram"] = is_engram_turn(r["content"])
        r["cost"] = cost_of(u, r["model"], overrides)
        r["ctx"] = (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
        r["tools"] = [b.get("name") for b in r["content"] if b.get("type") == "tool_use"]
        recs.append(r)
    return {"id": sid, "file": main_file, "reqs": recs, "prompt": (first_prompt or "").strip().replace("\n", " ")[:60],
            "ts": first_ts, "models": dict(models)}


def summarize(s):
    reqs = s["reqs"]
    main = [r for r in reqs if not r["sub"]]
    tot = sum(r["cost"] or 0 for r in reqs)
    unpriced = sum(1 for r in reqs if r["cost"] is None)
    eng = [r for r in reqs if r["engram"]]
    eng_cost = sum(r["cost"] or 0 for r in eng)
    fixed = 0.0
    if main:
        u0 = main[0]["usage"]; m0 = main[0]["model"]
        p = price_for(m0, [])
        if p:
            cc = u0.get("cache_creation") or {}
            w1h = cc.get("ephemeral_1h_input_tokens") or 0
            w5m = (u0.get("cache_creation_input_tokens") or 0) - w1h
            fixed = (w5m * p[0] * WRITE_5M + w1h * p[0] * WRITE_1H) / 1e6
    ctx = statistics.median([r["ctx"] for r in main]) if main else 0
    cr = sum(r["usage"].get("cache_read_input_tokens") or 0 for r in reqs)
    ci = sum((r["usage"].get("input_tokens") or 0) + (r["usage"].get("cache_creation_input_tokens") or 0) for r in reqs)
    hit = cr / (cr + ci) if (cr + ci) else 0
    out = sum(r["usage"].get("output_tokens") or 0 for r in reqs)
    return {"requests": len(reqs), "sub_requests": len(reqs) - len(main), "cost": tot, "fixed": fixed,
            "engram_reqs": len(eng), "engram_cost": eng_cost, "ctx": ctx, "hit": hit, "out": out,
            "unpriced": unpriced, "model": max(s["models"], key=s["models"].get) if s["models"] else "?"}


def fmt_money(x):
    return f"${x:6.2f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", default=os.getcwd(), help="repo path (default: cwd)")
    ap.add_argument("--transcript", action="append", help="explicit transcript .jsonl (repeatable)")
    ap.add_argument("--all", action="store_true", help="all sessions (default: last 20)")
    ap.add_argument("--price", action="append", default=[], help="override: <model-substring>=<in>,<out> $/MTok")
    ap.add_argument("--detail", help="per-request breakdown for the session whose id starts with this")
    ap.add_argument("--min-requests", type=int, default=2, help="skip sessions with fewer API requests")
    a = ap.parse_args()

    overrides = []
    for p in a.price:
        try:
            sub, io = p.split("="); i, o = io.split(",")
            overrides.append((sub.lower(), float(i), float(o)))
        except ValueError:
            sys.exit(f"bad --price {p!r}; want model=in,out")

    if a.transcript:
        files = a.transcript
    else:
        pd = project_dir_for(a.project)
        if not pd:
            sys.exit(f"no transcripts found for {a.project} under ~/.claude/projects (use --transcript)")
        files = sorted(glob.glob(os.path.join(pd, "*.jsonl")), key=os.path.getmtime)
        if not a.all:
            files = files[-20:]
    sessions = [load_session(f, overrides) for f in files]
    sessions = [s for s in sessions if len(s["reqs"]) >= a.min_requests]
    if not sessions:
        sys.exit("no sessions with API requests found")

    if a.detail:
        s = next((s for s in sessions if s["id"].startswith(a.detail)), None)
        if not s:
            sys.exit(f"no session starting with {a.detail}")
        print(f"session {s['id']}  {s['prompt']!r}")
        print(f"{'#':>3} {'when':19} {'sub':3} {'eng':3} {'ctx':>8} {'write':>7} {'read':>8} {'out':>6} {'cost':>7}  tools")
        for i, r in enumerate(s["reqs"], 1):
            u = r["usage"]
            print(f"{i:3d} {(r['ts'] or '')[:19]:19} {'sub' if r['sub'] else '':3} {'ENG' if r['engram'] else '':3} "
                  f"{r['ctx']:8d} {u.get('cache_creation_input_tokens') or 0:7d} {u.get('cache_read_input_tokens') or 0:8d} "
                  f"{u.get('output_tokens') or 0:6d} {fmt_money(r['cost'] or 0)}  {','.join(r['tools'])}")
        sm = summarize(s)
        print(f"\ntotal {fmt_money(sm['cost'])}  engram {fmt_money(sm['engram_cost'])} ({sm['engram_reqs']} of {sm['requests']} requests)")
        return

    print(f"{'session':10} {'started':16} {'model':16} {'req':>4} {'sub':>4} {'ctx':>7} {'hit':>4} {'fixed':>7} {'engram':>7} {'eng%':>5} {'total':>7}  first prompt")
    T = defaultdict(float)
    for s in sessions:
        sm = summarize(s)
        T["cost"] += sm["cost"]; T["engram"] += sm["engram_cost"]; T["fixed"] += sm["fixed"]; T["n"] += 1
        eng_pct = 100 * sm["engram_cost"] / sm["cost"] if sm["cost"] else 0
        print(f"{s['id'][:8]:10} {(s['ts'] or '')[:16]:16} {sm['model'][:16]:16} {sm['requests']:4d} {sm['sub_requests']:4d} "
              f"{int(sm['ctx']/1000):6d}K {int(100*sm['hit']):3d}% {fmt_money(sm['fixed'])} {fmt_money(sm['engram_cost'])} {eng_pct:4.0f}% {fmt_money(sm['cost'])}  {s['prompt']}"
              + ("  [unpriced model]" if sm["unpriced"] else ""))
    n = T["n"] or 1
    print(f"\n{int(n)} sessions: total {fmt_money(T['cost'])}  avg/session {fmt_money(T['cost']/n)}  "
          f"avg fixed {fmt_money(T['fixed']/n)}  avg engram {fmt_money(T['engram']/n)} ({100*T['engram']/T['cost'] if T['cost'] else 0:.0f}%)")
    print("ctx = median context tokens per request; hit = cache hit rate (near 0% means prompt caching is OFF -- every "
          "request pays full input price); fixed = first-request cache write; engram = requests that did Engram work.")


if __name__ == "__main__":
    main()
