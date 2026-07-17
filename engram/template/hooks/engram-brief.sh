#!/usr/bin/env bash
# engram-brief.sh -- Engram SessionStart hook (portable bash twin of engram-brief.ps1).
#
# Reads the SessionStart JSON payload from stdin, emits a short memory brief to
# stdout (Claude Code injects plain stdout directly into the session as context).
#
# LIMITATION: jq is NOT guaranteed to exist, so the two flat string fields we
# need ("source" and "cwd") are extracted with grep/sed. This assumes they are
# simple quoted JSON strings; exotic escaped values may mis-parse. Any parse
# failure degrades to defaults ($CLAUDE_PROJECT_DIR / $PWD), never to an error.
#
# Failure philosophy: every failure mode (bad JSON, no git, unreadable file,
# malformed frontmatter) silently skips that section. Always exits 0.

# Output buffer (bash 3.2 compatible: no mapfile, no associative arrays).
OUT_LINES=()
emit() { OUT_LINES+=("$1"); }

flush_and_exit() {
    # Hard cap ~80 lines of total output.
    local i=0
    local n=${#OUT_LINES[@]}
    while [ "$i" -lt "$n" ] && [ "$i" -lt 80 ]; do
        printf '%s\n' "${OUT_LINES[$i]}"
        i=$((i + 1))
    done
    exit 0
}

main() {
    # ---------- read stdin JSON ----------
    local raw source_val cwd_val
    raw=$(cat 2>/dev/null) || raw=""
    source_val=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    cwd_val=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    # JSON escapes backslashes; collapse '\\' back to '\' (Windows paths under Git Bash).
    cwd_val=${cwd_val//\\\\/\\}

    # ---------- resolve project root ----------
    local root="${CLAUDE_PROJECT_DIR:-}"
    [ -n "$root" ] || root="$cwd_val"
    [ -n "$root" ] || root="$PWD"

    local mem_dir="$root/.claude/memory"
    local memory_md="$mem_dir/MEMORY.md"
    [ -f "$memory_md" ] || exit 0    # no Engram here -> silent

    # ---------- compact: reminder + today's journal tail ----------
    if [ "$source_val" = "compact" ]; then
        emit '## Engram: post-compaction check'
        emit 'Context was just compacted. Anything learned before compaction and not yet journaled is at risk of being lost. If there are unlogged milestones, dead ends, or decisions from earlier in this session, append a journal entry now (follow /mem-journal), then continue.'
        # Re-inject the tail of today's journal: if a PreCompact capture hook just wrote
        # a draft, this is what carries it into the post-compaction context.
        local today_j="$mem_dir/journal/$(date '+%Y-%m-%d').md"
        if [ -r "$today_j" ]; then
            local jtail
            jtail=$(tail -n 25 "$today_j" 2>/dev/null)
            if [ -n "$jtail" ]; then
                emit ''
                emit "### Today's journal (tail)"
                while IFS= read -r tl; do emit "$tl"; done <<EOF_JTAIL
$jtail
EOF_JTAIL
            fi
        fi
        flush_and_exit
    fi

    # ---------- session brief (startup / resume / clear / anything else) ----------
    emit '## Engram session brief'
    emit 'Details live in .claude/memory/ (MEMORY.md is the index).'
    emit ''

    local memory_empty=0
    if grep -q 'STATUS: EMPTY' "$memory_md" 2>/dev/null; then memory_empty=1; fi

    # ----- Tasks: ## Now and ## Next sections from tasks.md (cap 15 lines) -----
    local tasks_md="$mem_dir/tasks.md"
    if [ -f "$tasks_md" ]; then
        local task_lines=() in_wanted=0 item_count=0 line sect
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                '## '*)
                    sect=$(printf '%s' "$line" | sed 's/^##[[:space:]]*//; s/[[:space:]]*$//')
                    if [ "$sect" = "Now" ] || [ "$sect" = "Next" ]; then
                        in_wanted=1
                        [ "${#task_lines[@]}" -lt 15 ] && task_lines+=("$line")
                    else
                        in_wanted=0
                    fi
                    ;;
                *)
                    if [ "$in_wanted" = 1 ] && [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] \
                       && [ "${#task_lines[@]}" -lt 15 ]; then
                        task_lines+=("$line")
                        item_count=$((item_count + 1))
                    fi
                    ;;
            esac
        done < "$tasks_md"
        emit '### Tasks'
        if [ "$item_count" -gt 0 ]; then
            local tl
            for tl in "${task_lines[@]}"; do emit "$tl"; done
        else
            emit 'No active tasks in tasks.md.'
        fi
        emit ''
    fi

    if [ "$memory_empty" = 1 ]; then
        emit 'Memory is empty - run /mem-init to bootstrap it from the codebase.'
        flush_and_exit
    fi

    # ----- Recent journal: 2 most recent daily files, last 2 entries each (~40 lines) -----
    emit '### Recent journal'
    local journal_dir="$mem_dir/journal"
    local jfiles
    # Non-recursive glob excludes journal/archive/; drop _*.md template files.
    jfiles=$(ls -1 "$journal_dir"/*.md 2>/dev/null | grep -v '/_[^/]*$' | sort -r | head -2)
    if [ -z "$jfiles" ]; then
        emit 'No journal entries yet.'
    else
        local budget=40 jf header starts from total
        while IFS= read -r jf; do
            [ "$budget" -le 0 ] && break
            [ -r "$jf" ] || continue
            # Date header: first '# ...' line (single hash), else derive from filename.
            header=$(grep -m1 '^#[[:space:]]' "$jf" 2>/dev/null)
            [ -n "$header" ] || header="# $(basename "$jf" .md)"
            emit "$header"; budget=$((budget - 1))
            # Entries start at lines beginning '## '; keep the last 2.
            starts=$(grep -n '^## ' "$jf" 2>/dev/null | cut -d: -f1)
            if [ -n "$starts" ]; then
                from=$(printf '%s\n' "$starts" | tail -2 | head -1)
                total=$(wc -l < "$jf" | tr -d '[:space:]')
                local i="$from" jl
                while [ "$i" -le "$total" ] && [ "$budget" -gt 0 ]; do
                    jl=$(sed -n "${i}p" "$jf")
                    if [ -n "$(printf '%s' "$jl" | tr -d '[:space:]')" ]; then
                        emit "$jl"; budget=$((budget - 1))
                    fi
                    i=$((i + 1))
                done
            fi
        done <<EOF_JFILES
$jfiles
EOF_JFILES
    fi
    emit ''

    # ----- Staleness: compare atlas card baselines against git history -----
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local atlas_dir="$mem_dir/atlas" cards
        cards=$(ls -1 "$atlas_dir"/*.md 2>/dev/null | grep -v '/_[^/]*$')
        if [ -n "$cards" ]; then
            local stale_list="" checked=0 card fm module verified paths behind
            local recent_mods=() recent_paths=()
            while IFS= read -r card; do
                [ -r "$card" ] || continue
                # Frontmatter = lines between the first pair of '---' fences.
                head -1 "$card" | grep -q '^---[[:space:]]*$' || continue
                fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$card")
                module=$(printf '%s\n' "$fm" | sed -n 's/^module:[[:space:]]*//p' | head -1 \
                    | sed 's/[[:space:]]*$//')
                verified=$(printf '%s\n' "$fm" | sed -n 's/^verified:[[:space:]]*//p' | head -1 \
                    | awk '{print $1}')
                paths=$(printf '%s\n' "$fm" \
                    | awk '/^paths:[[:space:]]*$/{f=1;next}
                           f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
                               gsub(/^["'\'']|["'\'']$/,""); print; next}
                           f{f=0}')
                [ -n "$module" ] || module=$(basename "$card" .md)
                [ -n "$paths" ] || continue    # malformed card: skip silently
                checked=$((checked + 1))
                # Path list -> argv array (bash 3.2: no mapfile).
                local patharr=() p
                while IFS= read -r p; do
                    [ -n "$p" ] && patharr+=("$p")
                done <<EOF_PATHS
$paths
EOF_PATHS
                recent_mods+=("$module")
                recent_paths+=("$paths")
                case "$verified" in
                    ""|0000000*)
                        stale_list="${stale_list:+$stale_list, }$module (unknown baseline)"
                        continue ;;
                esac
                if [ "$(git -C "$root" cat-file -t "$verified" 2>/dev/null)" != "commit" ]; then
                    stale_list="${stale_list:+$stale_list, }$module (unknown baseline)"
                    continue
                fi
                local loglines
                if ! loglines=$(git -C "$root" log --oneline "$verified..HEAD" -- "${patharr[@]}" 2>/dev/null); then
                    stale_list="${stale_list:+$stale_list, }$module (unknown baseline)"
                    continue
                fi
                behind=$(printf '%s\n' "$loglines" | grep -c . 2>/dev/null)
                [ -n "$behind" ] || behind=0
                if [ "$behind" -gt 0 ] 2>/dev/null; then
                    if [ "$behind" -eq 1 ]; then
                        stale_list="${stale_list:+$stale_list, }$module (1 commit behind)"
                    else
                        stale_list="${stale_list:+$stale_list, }$module ($behind commits behind)"
                    fi
                fi
            done <<EOF_CARDS
$cards
EOF_CARDS
            if [ "$checked" -gt 0 ]; then
                emit '### Atlas freshness'
                if [ -z "$stale_list" ]; then
                    emit "All $checked atlas cards fresh."
                else
                    emit "STALE cards - consider /mem-sync: $stale_list"
                fi
            fi

            # ----- Recent activity: commits in the last 24h touching each card's paths -----
            # Reuses the cards parsed above (module + paths); omit the section entirely
            # when nothing changed (silence beats noise). Same silent-failure discipline.
            local recent_line="" ri=0 rmod rpaths rn runit
            while [ "$ri" -lt "${#recent_mods[@]}" ]; do
                rmod="${recent_mods[$ri]}"
                rpaths="${recent_paths[$ri]}"
                ri=$((ri + 1))
                local rpatharr=() rp
                while IFS= read -r rp; do
                    [ -n "$rp" ] && rpatharr+=("$rp")
                done <<EOF_RPATHS
$rpaths
EOF_RPATHS
                [ "${#rpatharr[@]}" -gt 0 ] || continue
                local rlog
                rlog=$(git -C "$root" log --oneline --since=24.hours -- "${rpatharr[@]}" 2>/dev/null) || continue
                rn=$(printf '%s' "$rlog" | grep -c '.' 2>/dev/null)
                [ -n "$rn" ] || rn=0
                if [ "$rn" -gt 0 ] 2>/dev/null; then
                    if [ "$rn" -eq 1 ]; then runit="commit"; else runit="commits"; fi
                    recent_line="${recent_line:+$recent_line, }$rmod ($rn $runit)"
                fi
            done
            if [ -n "$recent_line" ]; then
                emit '### Recent activity (24h)'
                emit "$recent_line"
            fi
        fi
    fi

    flush_and_exit
}

# Never let an error escape: stderr suppressed, exit code forced to 0.
main 2>/dev/null
exit 0
