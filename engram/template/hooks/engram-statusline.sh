#!/usr/bin/env bash
# engram-statusline.sh -- Engram status line for Claude Code (portable bash twin
# of engram-statusline.ps1).
#
# Claude Code pipes status-line JSON to stdin and renders whatever this prints
# at the bottom of the UI. This shows the memory health of the CURRENT project:
#
#   🧠 2 now · 1 next │ atlas 8✓ │ ✎ today          (all fresh, journaled today)
#   🧠 no tasks │ atlas 2/9 stale │ ✎ 4d            (drifting -- /mem-sync time)
#   🧠 memory empty · run /mem-init                  (installed but not bootstrapped)
#   (nothing)                                        (project has no Engram)
#
# Registered ONCE in user settings (~/.claude/settings.json), not per-project:
# the script self-locates the project from the JSON payload (workspace.project_dir),
# so one registration covers every Engram-fied repo and stays blank elsewhere.
#
# LIMITATION: jq is NOT guaranteed to exist, so the fields we need are extracted
# with sed. This assumes they are simple quoted JSON strings; exotic escaped
# values may mis-parse. Any parse failure degrades to $CLAUDE_PROJECT_DIR / $PWD.
#
# PERFORMANCE: this runs after every assistant message (debounced), and the atlas
# pass costs ~2 git calls per card, so atlas counts are cached under $TMPDIR.
# The cache invalidates when HEAD moves, the card set changes, or any card file
# is edited -- staleness is commit-based, so within one HEAD it cannot change.
#
# Failure philosophy: any failure renders nothing (or silently drops that
# segment). Always exits 0.

main() {
    # ---------- read stdin JSON, resolve project root ----------
    local raw flat root
    raw=$(cat 2>/dev/null) || raw=""
    flat=$(printf '%s' "$raw" | tr -d '\n')
    root=$(printf '%s' "$flat" \
        | sed -n 's/.*"project_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$root" ] || root=$(printf '%s' "$flat" \
        | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-}"
    [ -n "$root" ] || root="$PWD"
    # JSON escapes backslashes; collapse '\\' to '\', then '\' to '/' (Windows).
    root=${root//\\\\/\\}
    root=${root//\\/\/}

    local mem="$root/.claude/memory"
    [ -f "$mem/MEMORY.md" ] || exit 0    # no Engram here -> blank status line

    local ESC=$'\033'
    local GRN="${ESC}[32m" YEL="${ESC}[33m" DIM="${ESC}[90m" RST="${ESC}[0m"

    # ---------- empty memory: single nudge ----------
    if grep -q 'STATUS: EMPTY' "$mem/MEMORY.md" 2>/dev/null; then
        printf '%s\n' "🧠 ${YEL}memory empty · run /mem-init${RST}"
        exit 0
    fi

    # ---------- tasks: count top-level bullets under ## Now / ## Next ----------
    local tasks_seg="" now_n=0 next_n=0 sect="" line
    if [ -f "$mem/tasks.md" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                '## Now'*)  sect=now ;;
                '## Next'*) sect=next ;;
                '## '*)     sect=other ;;
                '- '*|'* '*)
                    [ "$sect" = now ] && now_n=$((now_n + 1))
                    [ "$sect" = next ] && next_n=$((next_n + 1)) ;;
            esac
        done < "$mem/tasks.md"
    fi
    if [ "$now_n" -gt 0 ] || [ "$next_n" -gt 0 ]; then
        tasks_seg="${now_n} now${DIM} · ${RST}${next_n} next"
    else
        tasks_seg="${DIM}no tasks${RST}"
    fi

    # ---------- atlas freshness (cached; recompute only when git state moves) ----------
    local atlas_seg=""
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local head_sha cards
        head_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null)
        cards=$(ls -1 "$mem/atlas"/*.md 2>/dev/null | grep -v '/_[^/]*$')
        if [ -n "$head_sha" ] && [ -n "$cards" ]; then
            local key cache use_cache counts card
            key="$head_sha $(printf '%s' "$cards" | cksum | cut -d' ' -f1)"
            cache="${TMPDIR:-/tmp}/engram-statusline-$(printf '%s' "$root" | cksum | cut -d' ' -f1).cache"
            use_cache=0
            if [ -f "$cache" ] && [ "$(sed -n 1p "$cache" 2>/dev/null)" = "$key" ]; then
                use_cache=1
                while IFS= read -r card; do
                    if [ "$card" -nt "$cache" ]; then use_cache=0; break; fi
                done <<EOF_NT
$cards
EOF_NT
            fi
            if [ "$use_cache" = 1 ]; then
                counts=$(sed -n 2p "$cache" 2>/dev/null)
            else
                local checked=0 stale=0 fm verified paths loglines behind
                while IFS= read -r card; do
                    [ -r "$card" ] || continue
                    head -1 "$card" | grep -q '^---[[:space:]]*$' || continue
                    fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$card")
                    verified=$(printf '%s\n' "$fm" | sed -n 's/^verified:[[:space:]]*//p' \
                        | head -1 | awk '{print $1}')
                    paths=$(printf '%s\n' "$fm" \
                        | awk '/^paths:[[:space:]]*$/{f=1;next}
                               f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
                                   gsub(/^["'\'']|["'\'']$/,""); print; next}
                               f{f=0}')
                    [ -n "$paths" ] || continue    # malformed card: skip silently
                    checked=$((checked + 1))
                    local patharr=() p
                    while IFS= read -r p; do
                        [ -n "$p" ] && patharr+=("$p")
                    done <<EOF_PATHS
$paths
EOF_PATHS
                    # Unknown baseline counts as stale: the card needs /mem-sync either way.
                    case "$verified" in
                        ""|0000000*) stale=$((stale + 1)); continue ;;
                    esac
                    if [ "$(git -C "$root" cat-file -t "$verified" 2>/dev/null)" != "commit" ]; then
                        stale=$((stale + 1)); continue
                    fi
                    if ! loglines=$(git -C "$root" log --oneline "$verified..HEAD" -- "${patharr[@]}" 2>/dev/null); then
                        stale=$((stale + 1)); continue
                    fi
                    behind=$(printf '%s\n' "$loglines" | grep -c .)
                    if [ "$behind" -gt 0 ] 2>/dev/null; then stale=$((stale + 1)); fi
                done <<EOF_CARDS
$cards
EOF_CARDS
                counts="$checked $stale"
                { printf '%s\n' "$key"; printf '%s\n' "$counts"; } > "$cache" 2>/dev/null
            fi
            local n_checked n_stale
            n_checked=${counts%% *}
            n_stale=${counts##* }
            if [ "$n_checked" -gt 0 ] 2>/dev/null; then
                if [ "$n_stale" -gt 0 ] 2>/dev/null; then
                    atlas_seg="${YEL}atlas ${n_stale}/${n_checked} stale${RST}"
                else
                    atlas_seg="${GRN}atlas ${n_checked}✓${RST}"
                fi
            fi
        fi
    fi

    # ---------- journal recency: newest journal/YYYY-MM-DD.md ----------
    local jseg="" latest jdate today jsec tsec days
    latest=$(ls -1 "$mem/journal"/*.md 2>/dev/null | grep -v '/_[^/]*$' | sort | tail -1)
    if [ -z "$latest" ]; then
        jseg="${YEL}✎ none${RST}"
    else
        jdate=$(basename "$latest" .md)
        today=$(date +%Y-%m-%d 2>/dev/null)
        if [ "$jdate" = "$today" ]; then
            jseg="${GRN}✎ today${RST}"
        else
            case "$jdate" in
                [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                    # GNU date first (Git Bash / Linux), BSD date fallback (macOS).
                    jsec=$(date -d "$jdate" +%s 2>/dev/null) \
                        || jsec=$(date -j -f '%Y-%m-%d' "$jdate" +%s 2>/dev/null) || jsec=""
                    tsec=$(date -d "$today" +%s 2>/dev/null) \
                        || tsec=$(date -j -f '%Y-%m-%d' "$today" +%s 2>/dev/null) || tsec=""
                    if [ -n "$jsec" ] && [ -n "$tsec" ]; then
                        days=$(( (tsec - jsec) / 86400 ))
                        if [ "$days" -le 0 ]; then
                            jseg="${GRN}✎ today${RST}"
                        elif [ "$days" -ge 3 ]; then
                            jseg="${YEL}✎ ${days}d${RST}"
                        else
                            jseg="✎ ${days}d"
                        fi
                    else
                        jseg="✎ ${jdate}"
                    fi ;;
                *) jseg="" ;;    # non-date journal file: drop the segment
            esac
        fi
    fi

    # ---------- assemble ----------
    local out="🧠 ${tasks_seg}"
    [ -n "$atlas_seg" ] && out="$out ${DIM}│${RST} $atlas_seg"
    [ -n "$jseg" ] && out="$out ${DIM}│${RST} $jseg"
    printf '%s\n' "$out"
}

# Never let an error escape: stderr suppressed, exit code forced to 0.
main 2>/dev/null
exit 0
