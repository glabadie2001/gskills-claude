#!/usr/bin/env python3
"""Build the folder-first architecture X-ray: code only, base vs HEAD.

One command replaces the manual extract / worktree / fill-xray.html loop:

    python build_xray.py --base master --out xray.html \
        --src api --src app --src lib -- \
        --split api/adapters --prefix lib=app --exclude-file api/index.py

What it does (stdlib only, installs nothing):
  1. Extracts the FOLDER graph (modules = directories, no atlas) of the working
     tree at HEAD, and of a temporary `git worktree` of --base, with the SAME
     flags (a label flag on one side only makes every node diff as removed).
  2. Extracts the atlas-card graph at HEAD when `.claude/memory/atlas` exists.
  3. Fills xray.html with three sections, in the order that reads best:
       (1) folder diff base -> HEAD, (2) folder graph at HEAD alone,
       (3) atlas-card graph at HEAD.
  4. Removes the worktree and prints knots / two-way pairs for each graph.
Everything after a bare `--` goes to extract.py's folder mode unchanged.
Publish the file (Artifact tool) or open it in a browser.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
INPUT_MARK = "var INPUT = null; // __ENGRAM_INPUT__"


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw)


def git(*args, cwd="."):
    return run(["git", *args], cwd=cwd).stdout.strip()


def extract(out, root, src, flags, memory=None):
    """Run extract.py; return (mermaid text, summary line)."""
    cmd = [sys.executable, os.path.join(HERE, "extract.py"), "--root", root, "--out", out]
    for s in src:
        cmd += ["--src", s]
    cmd += flags
    if memory:
        cmd += ["--memory", memory]
    res = subprocess.run(cmd, text=True, capture_output=True)
    if res.returncode != 0:
        sys.exit(f"extract failed:\n{res.stdout}\n{res.stderr}")
    facts = [ln for ln in res.stdout.splitlines()
             if re.search(r"knots|two-way pairs|file-level import cycles", ln)]
    with open(os.path.join(out, "extracted.mmd"), encoding="utf-8") as f:
        return f.read(), " | ".join(x.strip() for x in facts)


def default_base():
    for cand in ("master", "main"):
        if subprocess.run(["git", "rev-parse", "--verify", "-q", cand],
                          capture_output=True).returncode == 0:
            return cand
    sys.exit("no master/main branch; pass --base REV")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--base", help="rev to diff against (default: master, else main)")
    ap.add_argument("--src", action="append", required=True,
                    help="top-level dir to walk (repeat); always pass it, else .venv/node_modules are walked")
    ap.add_argument("--out", default="xray.html", help="output HTML path")
    ap.add_argument("--project", default=None, help="title (default: repo name)")
    ap.add_argument("--alias", action="append", default=["@/=./"])
    ap.add_argument("--no-cards", action="store_true", help="skip the atlas-card section")
    ap.add_argument("folder_flags", nargs=argparse.REMAINDER,
                    help="after `--`: extra extract.py folder flags (--split, --group, --prefix, --exclude-file, --min-edge)")
    a = ap.parse_args()

    flags = [f for f in a.folder_flags if f != "--"]
    if "--min-edge" not in flags:
        flags += ["--min-edge", "1"]
    flags += ["--by-folder"]
    for al in a.alias:
        flags += ["--alias", al]

    root = git("rev-parse", "--show-toplevel")
    os.chdir(root)
    base = a.base or default_base()
    head = git("rev-parse", "--short", "HEAD")
    base_sha = git("rev-parse", "--short", base)
    tmp = tempfile.mkdtemp(prefix="xray-")
    wt = os.path.join(tmp, "base")
    sections, vitals = [], []
    try:
        git("worktree", "prune")
        git("worktree", "add", "-q", "--detach", wt, base)
        after, v_after = extract(os.path.join(tmp, "head"), root, a.src, flags)
        before, v_before = extract(os.path.join(tmp, "base_out"), wt, a.src, flags)
        vitals += [f"{base}@{base_sha}: {v_before}", f"HEAD@{head}: {v_after}"]
        sections.append({"title": f"Folder diff: {base} to HEAD, code only",
                         "before": before, "beforeLabel": f"{base}@{base_sha}",
                         "afterLabel": f"HEAD@{head}", "source": after})
        sections.append({"title": "Folder view at HEAD: code only, no atlas filing", "source": after})
        atlas = os.path.join(root, ".claude", "memory", "atlas")
        if not a.no_cards and os.path.isdir(atlas):
            cards, v_cards = extract(os.path.join(tmp, "cards"), root, a.src,
                                     [x for x in ["--alias", a.alias[-1]]],
                                     memory=os.path.join(root, ".claude", "memory"))
            vitals.append(f"cards: {v_cards}")
            sections.append({"title": "Atlas-card graph at HEAD", "source": cards})
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], capture_output=True)
        subprocess.run(["git", "worktree", "prune"], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)

    with open(os.path.join(HERE, "xray.html"), encoding="utf-8", newline="") as f:
        page = f.read()
    if INPUT_MARK not in page:
        sys.exit("xray.html template has no __ENGRAM_INPUT__ marker")
    project = a.project or os.path.basename(root)
    inp = {"project": f"{project} @ {head}", "generated": subprocess.check_output(
        ["git", "log", "-1", "--format=%cs"], text=True).strip(), "sections": sections}
    page = page.replace(INPUT_MARK, "var INPUT = " + json.dumps(inp) + ";")
    with open(a.out, "w", encoding="utf-8", newline="") as f:
        f.write(page)
    print("\n".join(vitals))
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
