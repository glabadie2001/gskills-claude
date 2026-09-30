#!/usr/bin/env python3
"""Engram /mem-arch extract — the module graph the code actually has.

Builds the file-level import graph (Python via `ast`, TypeScript/JavaScript via a
specifier scanner + tsconfig-style `@/` alias), collapses it onto the atlas cards'
`paths:` globs and reports what the hand-drawn Live diagram cannot know:

  * file-level import cycles per language (the only true "spaghetti" signal);
  * module edges with file-import counts, and the strongly connected components
    the X-ray will draw as knots;
  * for every two-way module pair, the WEAK direction listed file by file — the
    back-edges are what close a cycle, so that list is where the verdict lies
    (misfiled cross-cutting file vs. real coupling).

Atlas contract it honors (see atlas/_template.md):
  * `paths:` globs — the MOST SPECIFIC matching glob wins, so a card may claim one
    file out of another card's directory (e.g. a shared kernel claiming
    `lib/default-tenant.ts` inside `lib/**`);
  * `graph_exclude:` globs — files dropped from the graph entirely. Use it for
    composition roots and entrypoints (`api/dependencies.py`, `api/index.py`,
    workers that resolve ports from the root): they import everything BY DESIGN
    and would otherwise pull every module into one knot.

Folder mode (`--by-folder`, no atlas needed): modules are DIRECTORIES, so the
graph shows what the imports say even when card globs are wrong. A file's module
is its first `--folder-depth` path segments (default 2); files directly in a
top-level dir become "<dir> (loose files)". `--split DIR` goes one level deeper
under DIR (e.g. `api/adapters`); `--group PREFIX=NAME` maps a prefix to one node
(longest prefix wins, e.g. `app=app (routes)` with `app/api=app/api`);
`--prefix DIR=LABEL` puts LABEL/ in front of every module under top-level DIR
(e.g. `features=app` labels the front end's folders `app/features/...` beside
the backend's `api/...`; a `--group` name is used as given);
`--exclude-file GLOB` drops composition roots (the atlas `graph_exclude:` is
used too when --memory is given).

Usage (run from the repo root; stdlib only, installs nothing):
  python extract.py --memory .claude/memory [--out DIR] [--min-edge 2]
                    [--src DIR ...] [--exclude-dir NAME ...] [--alias @/=./]
  python extract.py --by-folder [--split DIR ...] [--group PREFIX=NAME ...]
                    [--prefix DIR=LABEL ...] [--exclude-file GLOB ...] [--folder-depth 2] [--src DIR ...]
Outputs in --out (default: the memory's `metrics/` dir is NOT touched — a temp dir):
  extracted.json   edges, examples, back-edges, SCCs, cycle counts
  extracted.mmd    Mermaid `graph TD` of module edges >= --min-edge (feed to render)
"""
from __future__ import annotations

import argparse
import ast
import collections
import fnmatch
import json
import os
import re
import sys

sys.setrecursionlimit(20000)

DEFAULT_EXCLUDE_DIRS = {
    "node_modules", ".next", "dist", "build", "out", ".git", ".venv", "venv",
    "__pycache__", ".turbo", "coverage", ".playwright-mcp",
}
TEST_DIR_NAMES = {"tests", "__tests__", "test", "e2e", "spec"}
TS_EXT = (".ts", ".tsx", ".js", ".jsx", ".mts", ".cts")
TS_RESOLVE = [".ts", ".tsx", ".js", ".jsx", "/index.ts", "/index.tsx", "/index.js"]
SPEC_RE = re.compile(
    r"""(?:^|[^\w$])(?:import|export)\s*(?:[^'";]*?\s+from\s*)?['"]([^'"]+)['"]"""
    r"""|(?:^|[^\w$])import\s*\(\s*['"]([^'"]+)['"]\s*\)"""
    r"""|(?:^|[^\w$])require\s*\(\s*['"]([^'"]+)['"]\s*\)""",
    re.M,
)


# ----------------------------------------------------------------- file walk
def walk(root: str, src_dirs: list[str] | None, exclude_dirs: set[str]):
    tops = src_dirs or [d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d))]
    for top in tops:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            dns[:] = [d for d in dns if d not in exclude_dirs and d not in TEST_DIR_NAMES and not d.startswith(".")]
            for f in fns:
                p = os.path.relpath(os.path.join(dp, f), root).replace(os.sep, "/")
                if is_test_file(p):
                    continue
                yield p


def is_test_file(p: str) -> bool:
    b = os.path.basename(p)
    return bool(re.search(r"\.(test|spec)\.[jt]sx?$", b) or re.match(r"(test_.*|.*_test)\.py$", b) or b == "conftest.py")


# -------------------------------------------------------------- python edges
def python_edges(root: str, files: list[str]) -> list[tuple[str, str]]:
    py = [f for f in files if f.endswith(".py")]
    # bare-import source roots: repo root + every top-level dir that holds .py files
    roots = {""} | {f.split("/")[0] for f in py if "/" in f}
    have = set(py)

    def resolve(mod: str, base: str):
        for r in ("", base):
            cand = (r + "/" if r else "") + mod
            for c in (cand + ".py", cand + "/__init__.py"):
                if c in have:
                    return c
        return None

    edges = []
    for p in py:
        try:
            tree = ast.parse(open(os.path.join(root, p), encoding="utf8", errors="replace").read())
        except SyntaxError:
            continue
        base = p.split("/")[0] if "/" in p else ""
        for n in ast.walk(tree):
            targets = []
            if isinstance(n, ast.ImportFrom):
                if n.level:
                    parts = p.rsplit("/", 1)[0].split("/") if "/" in p else []
                    parts = parts[: len(parts) - (n.level - 1)]
                    mod = "/".join(parts + ([n.module.replace(".", "/")] if n.module else []))
                    for a in n.names:
                        targets.append(resolve(mod + "/" + a.name, "") or resolve(mod, ""))
                else:
                    mod = (n.module or "").replace(".", "/")
                    if mod.split("/")[0] not in roots and not resolve(mod, base):
                        continue
                    for a in n.names:
                        targets.append(resolve(mod + "/" + a.name, base) or resolve(mod, base))
            elif isinstance(n, ast.Import):
                for a in n.names:
                    targets.append(resolve(a.name.replace(".", "/"), base))
            for t in targets:
                if t and t != p:
                    edges.append((p, t))
    return sorted(set(edges))


# ------------------------------------------------------------------ ts edges
def ts_edges(root: str, files: list[str], aliases: list[tuple[str, str]]) -> list[tuple[str, str]]:
    ts = [f for f in files if f.endswith(TS_EXT)]
    have = set(ts)

    def resolve(spec: str, frm: str):
        for a, b in aliases:
            if spec.startswith(a):  # alias → root-relative, never file-relative
                spec = b + spec[len(a):]
                break
        else:
            if not spec.startswith("."):
                return None  # bare package
            spec = os.path.join(os.path.dirname(frm), spec)
        spec = os.path.normpath(spec).replace(os.sep, "/")
        if spec.startswith("./"):
            spec = spec[2:]
        if spec in have:
            return spec
        for ext in TS_RESOLVE:
            if spec + ext in have:
                return spec + ext
        return None

    edges = []
    for p in ts:
        src = open(os.path.join(root, p), encoding="utf8", errors="replace").read()
        src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
        src = re.sub(r"(^|[^:\\])//.*$", r"\1", src, flags=re.M)
        for m in SPEC_RE.finditer(src):
            if re.match(r"\W?(import|export)\s+type\s", m.group(0)):
                continue  # type-only: erased at compile time, not a runtime edge
            spec = m.group(1) or m.group(2) or m.group(3)
            t = resolve(spec, p)
            if t and t != p:
                edges.append((p, t))
    return sorted(set(edges))


# ----------------------------------------------------------------- atlas map
def load_cards(memory: str):
    cards, excludes = {}, []
    adir = os.path.join(memory, "atlas")
    for f in sorted(os.listdir(adir)):
        if not f.endswith(".md") or f.startswith("_") or f.startswith("INDEX"):
            continue
        text = open(os.path.join(adir, f), encoding="utf8").read()
        if not text.startswith("---"):
            continue
        fm = text.split("---", 2)[1]
        module, key, globs = f[:-3], None, {"paths": [], "graph_exclude": []}
        for line in fm.splitlines():
            if re.match(r"^module:\s*", line):
                module = line.split(":", 1)[1].strip()
                key = None
            elif re.match(r"^(paths|graph_exclude):\s*$", line):
                key = line.split(":")[0]
            elif key and re.match(r"^\s+-\s*", line):
                globs[key].append(line.strip()[1:].strip().strip('"').strip("'"))
            else:
                key = None
        if globs["paths"]:
            cards[module] = globs["paths"]
        excludes += globs["graph_exclude"]
    return cards, excludes


def matcher(cards: dict[str, list[str]], excludes: list[str]):
    def hit(path: str, g: str) -> bool:
        return fnmatch.fnmatch(path, g) or (g.endswith("/**") and path.startswith(g[:-3] + "/"))

    def card_of(path: str):
        if any(hit(path, g) for g in excludes):
            return None
        best = None
        for c, gs in cards.items():
            for g in gs:
                if hit(path, g) and (best is None or len(g) > len(best[1])):
                    best = (c, g)
        return best[0] if best else None

    return card_of


def folder_matcher(depth: int, split: list[str], groups: list[tuple[str, str]], excludes: list[str],
                   prefixes: dict[str, str] | None = None):
    groups = sorted(groups, key=lambda g: -len(g[0]))
    split = {d.rstrip("/") for d in split}
    prefixes = prefixes or {}

    def label(path: str, name: str) -> str:
        top = path.split("/")[0]
        return f"{prefixes[top]}/{name}" if top in prefixes else name

    def folder_of(path: str):
        if any(fnmatch.fnmatch(path, g) for g in excludes):
            return None
        for prefix, name in groups:
            if path == prefix or path.startswith(prefix.rstrip("/") + "/"):
                return name
        parts = path.split("/")
        if len(parts) == 1:
            return "(root files)"
        n = depth
        while n < len(parts) - 1 and "/".join(parts[:n]) in split:
            n += 1
        if len(parts) - 1 < n:
            return label(path, "/".join(parts[:-1]) + " (loose files)")
        return label(path, "/".join(parts[:n]))

    return folder_of


def mermaid_id(name: str) -> str:
    return name if re.fullmatch(r"[A-Za-z0-9_-]+", name) else re.sub(r"[^A-Za-z0-9_]", "_", name)


# -------------------------------------------------------------------- graphs
def sccs(edges):
    g = collections.defaultdict(set)
    for a, b in edges:
        g[a].add(b)
        g.setdefault(b, set())
    idx, low, st, on, out, c = {}, {}, [], set(), [], [0]

    def strong(v):
        idx[v] = low[v] = c[0]
        c[0] += 1
        st.append(v)
        on.add(v)
        for w in g[v]:
            if w not in idx:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], idx[w])
        if low[v] == idx[v]:
            comp = []
            while True:
                w = st.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1:
                out.append(sorted(comp))

    for v in list(g):
        if v not in idx:
            strong(v)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--memory", help="Engram memory dir (holds atlas/); required unless --by-folder")
    ap.add_argument("--by-folder", action="store_true", help="modules = directories, not atlas cards")
    ap.add_argument("--folder-depth", type=int, default=2, help="--by-folder: path segments per module")
    ap.add_argument("--split", action="append", default=[], help="--by-folder: go one level deeper under DIR")
    ap.add_argument("--group", action="append", default=[], help="--by-folder: PREFIX=NAME, one node for a prefix")
    ap.add_argument("--prefix", action="append", default=[], help="--by-folder: DIR=LABEL, label modules under DIR as LABEL/...")
    ap.add_argument("--exclude-file", action="append", default=[], help="--by-folder: glob of files to drop")
    ap.add_argument("--root", default=".", help="repo root (default: cwd)")
    ap.add_argument("--out", default=None, help="output dir (default: <root>/.engram-extract)")
    ap.add_argument("--src", action="append", help="limit the walk to these top-level dirs")
    ap.add_argument("--exclude-dir", action="append", default=[], help="extra dir names to skip")
    ap.add_argument("--alias", action="append", default=["@/=./"], help="TS alias PREFIX=REPLACEMENT")
    ap.add_argument("--min-edge", type=int, default=2, help="Mermaid: drop module edges below this count")
    ap.add_argument("--skip-card", action="append", default=[], help="cards to leave out of the graph (tests, dev spikes)")
    a = ap.parse_args()
    if not a.by_folder and not a.memory:
        ap.error("--memory is required unless --by-folder")

    root = os.path.abspath(a.root)
    files = list(walk(root, a.src, DEFAULT_EXCLUDE_DIRS | set(a.exclude_dir)))
    aliases = [tuple(x.split("=", 1)) for x in a.alias]
    py, ts = python_edges(root, files), ts_edges(root, files, aliases)
    cards, excludes = load_cards(a.memory) if a.memory else ({}, [])
    if a.by_folder:
        excludes = excludes + a.exclude_file
        groups = [tuple(x.split("=", 1)) for x in a.group]
        prefixes = dict(tuple(x.split("=", 1)) for x in a.prefix)
        card_of = folder_matcher(a.folder_depth, a.split, groups, excludes, prefixes)
    else:
        card_of = matcher(cards, excludes)

    mod_edges = collections.Counter()
    examples = collections.defaultdict(list)
    unmapped = collections.Counter()
    for s, t in py + ts:
        cs, ct = card_of(s), card_of(t)
        if cs is None and not any(fnmatch.fnmatch(s, g) for g in excludes):
            unmapped[s.rsplit("/", 1)[0] if "/" in s else s] += 1
        if not cs or not ct or cs == ct or cs in a.skip_card or ct in a.skip_card:
            continue
        mod_edges[(cs, ct)] += 1
        examples[(cs, ct)].append(f"{s} -> {t}")

    knots = sccs(list(mod_edges))
    pairs = sorted({tuple(sorted(k)) for k in mod_edges if (k[1], k[0]) in mod_edges})
    back = []
    for x, y in pairs:
        if mod_edges[(x, y)] < mod_edges[(y, x)]:
            x, y = y, x
        back.append({"strong": f"{x} -> {y}", "strong_n": mod_edges[(x, y)],
                     "weak": f"{y} -> {x}", "weak_n": mod_edges[(y, x)],
                     "weak_files": sorted(set(examples[(y, x)]))})
    py_cycles, ts_cycles = sccs(py), sccs(ts)

    out = a.out or os.path.join(root, ".engram-extract")
    os.makedirs(out, exist_ok=True)
    report = {
        "files": {"python": sum(f.endswith(".py") for f in files), "ts": sum(f.endswith(TS_EXT) for f in files)},
        "file_edges": {"python": len(py), "ts": len(ts)},
        "file_cycles": {"python": [c[:12] for c in py_cycles], "ts": [c[:12] for c in ts_cycles]},
        "excluded_globs": excludes,
        "module_edges": {f"{s}|{t}": n for (s, t), n in sorted(mod_edges.items(), key=lambda kv: -kv[1])},
        "examples": {f"{s}|{t}": v[:6] for (s, t), v in examples.items()},
        "knots": knots,
        "two_way_pairs": back,
        "unmapped_dirs": dict(unmapped.most_common(20)),
    }
    json.dump(report, open(os.path.join(out, "extracted.json"), "w", encoding="utf8"), indent=1)
    shown = [(s, t, n) for (s, t), n in sorted(mod_edges.items(), key=lambda kv: -kv[1]) if n >= a.min_edge]
    names = sorted({x for s, t, _ in shown for x in (s, t)})
    mm = ["graph TD"] + [f'  {mermaid_id(x)}["{x}"]' for x in names if mermaid_id(x) != x]
    mm += [f"  {mermaid_id(s)} -->|{n}| {mermaid_id(t)}" for s, t, n in shown]
    open(os.path.join(out, "extracted.mmd"), "w", encoding="utf8").write("\n".join(mm) + "\n")

    print(f"files: {report['files']}   file edges: {report['file_edges']}")
    print(f"file-level import cycles: python={len(py_cycles)} ts={len(ts_cycles)}")
    print(f"module edges: {len(mod_edges)}   knots: {[len(k) for k in knots] or 'none'}")
    print(f"excluded (graph_exclude): {excludes or 'none'}")
    if unmapped and not a.by_folder:
        print(f"unmapped dirs (no card claims them): {dict(unmapped.most_common(8))}")
    print(f"\ntwo-way pairs: {len(back)}  (weak direction = the back-edges that close the cycle)")
    for b in sorted(back, key=lambda b: -b["weak_n"]):
        print(f"  {b['strong']}: {b['strong_n']}   BACK {b['weak']}: {b['weak_n']}")
        for f in b["weak_files"][:8]:
            print(f"      {f}")
    print(f"\nwrote {out}/extracted.json and extracted.mmd")


if __name__ == "__main__":
    main()
