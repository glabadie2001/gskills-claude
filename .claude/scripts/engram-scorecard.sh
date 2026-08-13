#!/usr/bin/env bash
# engram-scorecard.sh -- Engram deterministic scorecard generator (portable bash twin of engram-scorecard.ps1).
#
# Zero-token metrics: reads .claude/memory/metrics/events.jsonl (the log DB) and
# regenerates .claude/memory/metrics/scorecard.md. Both twins must emit a
# byte-identical scorecard for identical inputs (the only input besides the log is
# today's date, for the 30-day window). Stat definitions live in the .ps1 header.
#
# Usage: engram-scorecard.sh [--root <repo>]
#   --root  repo root (default: current dir); resolves satellite pins like the linter
#
# Exit code: 0 on success (including "no events yet"), 1 if the memory dir is missing.
#
# Portability: bash 3.2, POSIX awk, jq not required, LF endings.

# ---------- args ----------
ARG_ROOT="."
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ARG_ROOT="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

# ---------- per-OS dispatch: Git Bash process spawns are slow on Windows ----------
case "${OSTYPE:-}" in
    msys*|cygwin*)
        _psf="${0%/*}/engram-scorecard.ps1"
        if [ -f "$_psf" ] && command -v powershell.exe >/dev/null 2>&1; then
            command -v cygpath >/dev/null 2>&1 && _psf=$(cygpath -w "$_psf")
            exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$_psf" -Root "$ARG_ROOT"
        fi
        ;;
esac

# ---------- resolve + normalize root (same rung order as engram-lint) ----------
root=$(cd "$ARG_ROOT" 2>/dev/null && pwd)
[ -n "$root" ] || root="${ARG_ROOT%/}"
root="${root%/}"

if [ ! -f "$root/.claude/memory/MEMORY.md" ]; then
    resolved=""
    pin_path="$root/.claude/engram-root"
    if [ -f "$pin_path" ]; then
        pin_line=""
        while IFS= read -r pl || [ -n "$pl" ]; do pin_line="$pl"; break; done < "$pin_path"
        pin_line=$(printf '%s' "$pin_line" | tr -d '\r' | sed 's/^ *//; s/ *$//')
        if [ -n "$pin_line" ] && [ -f "$root/$pin_line/.claude/memory/MEMORY.md" ]; then
            resolved="$root/$pin_line"
        fi
    fi
    if [ -z "$resolved" ]; then
        for d in "$root"/*/; do
            [ -f "${d}.claude/memory/MEMORY.md" ] || continue
            resolved="${d%/}"
            break
        done
    fi
    [ -n "$resolved" ] && root="$resolved"
fi

memdir="$root/.claude/memory"
if [ ! -f "$memdir/MEMORY.md" ]; then
    echo "engram-scorecard: no memory at $memdir"
    exit 1
fi
events="$memdir/metrics/events.jsonl"
out="$memdir/metrics/scorecard.md"
mkdir -p "$memdir/metrics"

cutoff=$(date -d "-30 days" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || echo 1970-01-01)
idx=$(wc -l < "$memdir/MEMORY.md" | tr -d '[:space:]')

src="$events"
[ -f "$src" ] || src=/dev/null

awk -v OUT="$out" -v CUTOFF="$cutoff" -v IDX="$idx" '
# ---------- shared rounding (identical to the ps1 twin) ----------
function fl(x) { return (x == int(x) || x > 0) ? int(x) : int(x) - 1 }
function fmt1(x) { return sprintf("%.1f", fl(x * 10 + 0.5) / 10) }
function pct(n, d) { return fl(n * 100 / d + 0.5) "%" }

# ---------- flat-JSON field extraction (q is cut out of the line first) ----------
function getstr(line, key,    pat, i, s, j) {
    pat = "\"" key "\":\""
    i = index(line, pat); if (!i) return "\001"
    s = substr(line, i + length(pat))
    j = index(s, "\""); if (!j) return "\001"
    return substr(s, 1, j - 1)
}
function getraw(line, key,    pat, i, s) {
    pat = "\"" key "\":"
    i = index(line, pat); if (!i) return "\001"
    s = substr(line, i + length(pat))
    if (s ~ /^"/)     return "str"
    if (s ~ /^null/)  return "null"
    if (s ~ /^true/)  return "true"
    if (s ~ /^false/) return "false"
    if (match(s, /^-?[0-9]+(\.[0-9]+)?/)) return substr(s, 1, RLENGTH)
    return "\001"
}
function present(v) { return (v != "\001" && v != "null") }

{
    line = $0
    sub(/^[ \t\r]+/, "", line); sub(/[ \t\r]+$/, "", line)
    if (line == "") next

    # cut the free-text q field out (escape-aware scan) so later key lookups are safe
    q = ""
    i = index(line, "\"q\":\"")
    if (i) {
        rest = substr(line, i + 5)
        n = length(rest); j = 0; esc = 0
        for (k = 1; k <= n; k++) {
            c = substr(rest, k, 1)
            if (esc) { esc = 0; continue }
            if (c == "\\") { esc = 1; continue }
            if (c == "\"") { j = k; break }
        }
        if (j) {
            q = substr(rest, 1, j - 1)
            gsub(/\\"/, "\"", q); gsub(/\\\\/, "\\", q)
            line = substr(line, 1, i - 1) substr(line, i + 5 + j)
        }
    }

    t = getstr(line, "t")
    if (t == "recall") {
        nr++
        ts = getstr(line, "ts")
        model = getstr(line, "model")
        outc = getstr(line, "outcome")
        fr = getraw(line, "files_read")
        mfr = getraw(line, "mem_files_read")
        mg = getraw(line, "mem_greps")
        mgl = getraw(line, "mem_grep_lines")
        de = getraw(line, "dead_end_cited")
        bf = getraw(line, "backfilled")
        rec = (length(ts) >= 10 && substr(ts, 1, 10) >= CUTOFF)

        if (outc == "hit") { a_hit++; if (rec) r_hit++ }
        else if (outc == "verified") { a_ver++; if (rec) r_ver++ }
        else if (outc == "miss") {
            a_miss++; if (rec) r_miss++
            if (bf != "\001" && bf != "null") { a_bf++; if (rec) r_bf++ }
            nq = tolower(q)
            gsub(/[^a-z0-9]+/, " ", nq); sub(/^ +/, "", nq); sub(/ +$/, "", nq)
            if (nq != "") {
                if (nq in seenq) { if (!(nq in dupq)) { dupq[nq] = 1; duplist[++ndup] = nq } }
                else seenq[nq] = 1
            }
        }
        if (rec) r_n++
        if (present(fr)) {
            a_fs += fr; a_fc++
            if (rec) { r_fs += fr; r_fc++ }
            if (outc == "hit" || outc == "verified") { h_fs += fr; h_fc++ }
            else if (outc == "miss") { x_fs += fr; x_fc++ }
        }
        if (present(mfr)) { c_mfs += mfr; c_mfc++ }
        if (present(mgl)) { c_gls += mgl; c_glc++ }
        if (present(mg)) { g_den++; if (mg + 0 > 0) g_num++ }
        if (de == "true") dead++
        if (outc == "hit" || outc == "verified") nok++

        if (model != "\001" && model != "") {
            if (!(model in mseen)) { mseen[model] = 1; mlist[++nm] = model }
            m_n[model]++
            if (outc == "hit" || outc == "verified") m_ok[model]++
            if (present(fr)) { m_fs[model] += fr; m_fc[model]++ }
            if (present(mfr)) { m_mfs[model] += mfr; m_mfc[model]++ }
        }
    } else if (t == "sync") {
        ns++
        s_ts[ns] = getstr(line, "ts"); s_head[ns] = getstr(line, "head")
        s_cards[ns] = getraw(line, "cards"); s_fresh[ns] = getraw(line, "fresh")
        s_mb[ns] = getraw(line, "mean_behind"); s_il[ns] = getraw(line, "index_lines")
        s_e14[ns] = getraw(line, "journal_entries_14d")
    }
}

function rrow(label, n, hit, ver, miss, bfn, fs, fc,    hr, br, mf) {
    hr = "--"; if (n > 0) hr = pct(hit + ver, n)
    br = "--"; if (miss > 0) br = pct(bfn, miss)
    mf = "--"; if (fc > 0) mf = fmt1(fs / fc)
    print "| " label " | " n+0 " | " hit+0 " | " ver+0 " | " miss+0 " | " hr " | " br " | " mf " |" > OUT
}

END {
    print "# Engram scorecard" > OUT
    print "<!-- GENERATED by engram-scorecard from metrics/events.jsonl -- do not hand-edit. -->" > OUT
    print "" > OUT
    print "## Retrieval" > OUT
    print "" > OUT
    if (nr + 0 == 0) {
        print "*No recall events yet -- /mem-recall logs one event per memory-served question; this table populates once recalls happen.*" > OUT
        print "" > OUT
    }
    print "| Window | Recalls | Hit | Verified | Miss | Hit rate | Backfill rate | Mean files read |" > OUT
    print "|--------|---------|-----|----------|------|----------|---------------|-----------------|" > OUT
    rrow("all-time", nr, a_hit, a_ver, a_miss, a_bf, a_fs, a_fc)
    rrow("last 30d", r_n, r_hit, r_ver, r_miss, r_bf, r_fs, r_fc)
    print "" > OUT

    if (nm + 0 > 1) {
        # ordinal sort of model names (matches StringComparer.Ordinal in the ps1 twin)
        for (x = 1; x <= nm; x++) for (y = x + 1; y <= nm; y++)
            if (mlist[y] < mlist[x]) { tmp = mlist[x]; mlist[x] = mlist[y]; mlist[y] = tmp }
        print "## Per-model" > OUT
        print "" > OUT
        print "| Model | Recalls | Hit rate | Mean files_read | Mean mem_files_read |" > OUT
        print "|-------|---------|----------|-----------------|---------------------|" > OUT
        for (x = 1; x <= nm; x++) {
            mo = mlist[x]
            mf = "--"; if (m_fc[mo] + 0 > 0) mf = fmt1(m_fs[mo] / m_fc[mo])
            mm = "--"; if (m_mfc[mo] + 0 > 0) mm = fmt1(m_mfs[mo] / m_mfc[mo])
            print "| " mo " | " m_n[mo]+0 " | " pct(m_ok[mo]+0, m_n[mo]) " | " mf " | " mm " |" > OUT
        }
        print "" > OUT
    }

    marg = "no recall data"; imr = "--"; ben = "no recall data"
    if (nr + 0 > 0) {
        a = "n/a"; if (c_mfc + 0 > 0) a = fmt1(c_mfs / c_mfc)
        b = "n/a"; tok = ""
        if (c_glc + 0 > 0) { b = fmt1(c_gls / c_glc); tok = " (~" fl(c_gls / c_glc * 10 + 0.5) " tok)" }
        if (c_mfc + 0 == 0 && c_glc + 0 == 0) marg = "n/a (no field data)"
        else marg = a " mem files + " b " grep lines" tok " per recall"
        if (g_den + 0 > 0) imr = pct(g_num + 0, g_den)
        if (h_fc + 0 > 0 && x_fc + 0 > 0)
            ben = "mean files_read miss " fmt1(x_fs / x_fc) " vs hit " fmt1(h_fs / h_fc) " -> ~" fmt1(x_fs / x_fc - h_fs / h_fc) " saved per hit x " nok+0 " hits"
        else
            ben = "-- (need both hits and misses)"
    }
    print "**Cost ledger:** fixed overhead " IDX+0 " index lines (always loaded); marginal overhead " marg "; index-miss rate " imr "; benefit " ben "." > OUT

    rm = "none"
    if (ndup + 0 > 0) { rm = duplist[1]; for (x = 2; x <= ndup; x++) rm = rm "; " duplist[x] }
    print "**Dead-end saves:** " dead+0 " cited. **Repeat misses (exact):** " rm " -- semantic near-duplicates are judged by /mem-sync." > OUT
    print "" > OUT

    print "## Health trend (sync snapshots)" > OUT
    print "" > OUT
    if (ns + 0 == 0) {
        print "*No sync snapshots yet -- /mem-sync appends one per run.*" > OUT
    } else {
        print "| Date | HEAD | Cards | Fresh | Mean behind | Index lines | Entries 14d |" > OUT
        print "|------|------|-------|-------|-------------|-------------|-------------|" > OUT
        start = 1; if (ns > 6) start = ns - 5
        for (x = start; x <= ns; x++) {
            mb = "--"; if (present(s_mb[x])) mb = fmt1(s_mb[x] + 0)
            print "| " s_ts[x] " | " s_head[x] " | " s_cards[x]+0 " | " s_fresh[x]+0 " | " mb " | " s_il[x]+0 " | " s_e14[x]+0 " |" > OUT
        }
    }
    close(OUT)
    print "engram-scorecard: " nr+0 " recalls, " ns+0 " syncs -> .claude/memory/metrics/scorecard.md"
}
' "$src"
exit 0
