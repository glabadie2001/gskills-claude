#!/usr/bin/env bash
# engram-brief.sh -- Engram SessionStart hook (portable bash twin of engram-brief.ps1).
#
# Reads the SessionStart JSON payload from stdin, emits a short memory brief to
# stdout (Claude Code injects plain stdout directly into the session as context).
#
# LIMITATION: jq is NOT guaranteed to exist, so the two flat string fields we
# need ("source" and "cwd") are extracted with a bash regex. This assumes they
# are simple quoted JSON strings; exotic escaped values may mis-parse. Any parse
# failure degrades to defaults ($CLAUDE_PROJECT_DIR / $PWD), never to an error.
#
# PERFORMANCE: SessionStart hooks run synchronously on startup AND on /clear, and
# Claude Code kills them at the configured timeout (30s), so this must be cheap on
# the slowest supported platform (Git Bash on Windows, where every fork costs tens
# of ms and every git.exe launch ~100-200ms). Rules: no per-line or per-card
# pipelines -- frontmatter, tasks and journals are parsed in pure bash; staleness
# is ONE `git rev-list --count` per card; recent activity is ONE repo-wide git log;
# and the atlas result is cached under $TMPDIR keyed on HEAD + the card set, so a
# repeat start on the same commit costs a single `git rev-parse`.
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

# Trim leading/trailing whitespace (and a stray CR) in place: trim VAR
trim() {
    local v="${!1}"
    v=${v%$'\r'}
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf -v "$1" '%s' "$v"
}

# parse_frontmatter <file> -> FM_MODULE, FM_VERIFIED, FM_PATHS (newline-separated).
# Returns 1 if the file has no leading '---' fence. Pure bash: zero processes.
parse_frontmatter() {
    FM_MODULE="" FM_VERIFIED="" FM_PATHS=""
    local line first=1 in_paths=0 re_item='^[[:space:]]+-[[:space:]]*(.*)$'
    local re_paths='^paths:[[:space:]]*$' re_mod='^module:[[:space:]]*(.*)$'
    local re_ver='^verified:[[:space:]]*([^[:space:]]+)'
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        if [ "$first" = 1 ]; then
            first=0
            local t="$line"; trim t
            [ "$t" = "---" ] || return 1
            continue
        fi
        local t="$line"; trim t
        [ "$t" = "---" ] && break
        if [ "$in_paths" = 1 ]; then
            if [[ $line =~ $re_item ]]; then
                local p="${BASH_REMATCH[1]}"; trim p
                p=${p#\"}; p=${p%\"}; p=${p#\'}; p=${p%\'}
                [ -n "$p" ] && FM_PATHS="${FM_PATHS:+$FM_PATHS
}$p"
                continue
            fi
            in_paths=0
        fi
        if [[ $line =~ $re_paths ]]; then
            in_paths=1
        elif [ -z "$FM_MODULE" ] && [[ $line =~ $re_mod ]]; then
            FM_MODULE="${BASH_REMATCH[1]}"; trim FM_MODULE
        elif [ -z "$FM_VERIFIED" ] && [[ $line =~ $re_ver ]]; then
            FM_VERIFIED="${BASH_REMATCH[1]}"
        fi
    done < "$1"
    return 0
}

# behind_count <root> <verified> <paths...> -> prints N commits since <verified>
# touching <paths>, or "?" for an unknown/missing baseline. One git call.
behind_count() {
    local root="$1" verified="$2"; shift 2
    case "$verified" in
        ""|0000000*) printf '?'; return ;;
    esac
    local n
    if n=$(git -C "$root" rev-list --count "$verified..HEAD" -- "$@" 2>/dev/null) \
       && [ -n "$n" ]; then
        printf '%s' "$n"
    else
        printf '?'
    fi
}

# path_matches <file> <pathspec> -> 0 if the git pathspec covers the file.
# Mirrors git's default (non-:(glob)) wildmatch closely enough: '*' and '**'
# cross '/', and a bare directory covers everything beneath it.
path_matches() {
    case "$1" in
        $2|$2/*) return 0 ;;
    esac
    return 1
}

main() {
    # ---------- read stdin JSON ----------
    local raw source_val="" cwd_val=""
    raw=$(cat 2>/dev/null) || raw=""
    local re_src='"source"[[:space:]]*:[[:space:]]*"([^"]*)"'
    local re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
    [[ $raw =~ $re_src ]] && source_val="${BASH_REMATCH[1]}"
    [[ $raw =~ $re_cwd ]] && cwd_val="${BASH_REMATCH[1]}"
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

    local memory_empty=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *'STATUS: EMPTY'*) memory_empty=1; break ;; esac
    done < "$memory_md"

    # ----- Tasks: ## Now and ## Next sections from tasks.md (cap 15 lines) -----
    local tasks_md="$mem_dir/tasks.md"
    if [ -f "$tasks_md" ]; then
        local task_lines=() in_wanted=0 item_count=0 sect t
        while IFS= read -r line || [ -n "$line" ]; do
            line=${line%$'\r'}
            case "$line" in
                '## '*)
                    sect="${line#\#\#}"; trim sect
                    if [ "$sect" = "Now" ] || [ "$sect" = "Next" ]; then
                        in_wanted=1
                        [ "${#task_lines[@]}" -lt 15 ] && task_lines+=("$line")
                    else
                        in_wanted=0
                    fi
                    ;;
                *)
                    t="$line"; trim t
                    if [ "$in_wanted" = 1 ] && [ -n "$t" ] && [ "${#task_lines[@]}" -lt 15 ]; then
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
    # Non-recursive glob (sorted ascending) excludes journal/archive/; drop _*.md templates.
    local jall=() jf
    for jf in "$journal_dir"/*.md; do
        [ -f "$jf" ] || continue
        case "${jf##*/}" in _*) continue ;; esac
        jall+=("$jf")
    done
    local jn=${#jall[@]}
    if [ "$jn" -eq 0 ]; then
        emit 'No journal entries yet.'
    else
        local budget=40 ji=$((jn - 1)) jstop=$((jn - 2))
        [ "$jstop" -lt 0 ] && jstop=0
        while [ "$ji" -ge "$jstop" ]; do
            jf="${jall[$ji]}"; ji=$((ji - 1))
            [ "$budget" -le 0 ] && break
            [ -r "$jf" ] || continue
            # Read the file once; find the date header and the entry starts.
            local jl=() header="" starts=() k=0
            while IFS= read -r line || [ -n "$line" ]; do
                line=${line%$'\r'}
                jl+=("$line")
                case "$line" in
                    '## '*) starts+=("$k") ;;
                    '#'[[:space:]]*) [ -n "$header" ] || header="$line" ;;
                esac
                k=$((k + 1))
            done < "$jf"
            if [ -z "$header" ]; then
                header="${jf##*/}"; header="# ${header%.md}"
            fi
            emit "$header"; budget=$((budget - 1))
            local ns=${#starts[@]}
            if [ "$ns" -gt 0 ]; then
                # Entries start at '## '; keep the last 2.
                local from
                if [ "$ns" -ge 2 ]; then from="${starts[$((ns - 2))]}"; else from="${starts[0]}"; fi
                local i="$from"
                while [ "$i" -lt "$k" ] && [ "$budget" -gt 0 ]; do
                    t="${jl[$i]}"; trim t
                    if [ -n "$t" ]; then
                        emit "${jl[$i]}"; budget=$((budget - 1))
                    fi
                    i=$((i + 1))
                done
            fi
        done
    fi
    emit ''

    # ----- Staleness: compare atlas card baselines against git history -----
    local head_sha
    head_sha=$(git -C "$root" rev-parse HEAD 2>/dev/null) || head_sha=""
    if [ -n "$head_sha" ]; then
        local atlas_dir="$mem_dir/atlas" cards=() card
        for card in "$atlas_dir"/*.md; do
            [ -f "$card" ] || continue
            case "${card##*/}" in _*) continue ;; esac
            cards+=("$card")
        done
        if [ "${#cards[@]}" -gt 0 ]; then
            # Parse every card once (pure bash). Parallel arrays: module + paths.
            local mods=() pathsets=() vers=() checked=0 ci
            for card in "${cards[@]}"; do
                [ -r "$card" ] || continue
                parse_frontmatter "$card" || continue
                [ -n "$FM_PATHS" ] || continue    # malformed card: skip silently
                local module="$FM_MODULE"
                [ -n "$module" ] || { module="${card##*/}"; module="${module%.md}"; }
                mods+=("$module")
                pathsets+=("$FM_PATHS")
                # verified shas ride along, one per card, for the staleness pass
                vers[$checked]="$FM_VERIFIED"
                checked=$((checked + 1))
            done

            if [ "$checked" -gt 0 ]; then
                # -- cache: staleness cannot change within one HEAD unless a card is edited --
                local key="$head_sha ${cards[*]}" cache use_cache=0 stale_list=""
                local cache_dir="${TMPDIR:-/tmp}" tag="${root//[^A-Za-z0-9]/_}"
                tag=${tag:$(( ${#tag} > 120 ? ${#tag} - 120 : 0 ))}
                cache="$cache_dir/engram-brief-$tag.cache"
                if [ -f "$cache" ]; then
                    local ckey="" cval=""
                    { IFS= read -r ckey; IFS= read -r cval; } < "$cache" 2>/dev/null
                    if [ "$ckey" = "$key" ]; then
                        use_cache=1
                        for card in "${cards[@]}"; do
                            if [ "$card" -nt "$cache" ]; then use_cache=0; break; fi
                        done
                        [ "$use_cache" = 1 ] && stale_list="$cval"
                    fi
                fi
                if [ "$use_cache" = 0 ]; then
                    ci=0
                    while [ "$ci" -lt "$checked" ]; do
                        local patharr=() p behind
                        while IFS= read -r p; do
                            [ -n "$p" ] && patharr+=("$p")
                        done <<EOF_PATHS
${pathsets[$ci]}
EOF_PATHS
                        behind=$(behind_count "$root" "${vers[$ci]}" "${patharr[@]}")
                        if [ "$behind" = "?" ]; then
                            stale_list="${stale_list:+$stale_list, }${mods[$ci]} (unknown baseline)"
                        elif [ "$behind" -eq 1 ] 2>/dev/null; then
                            stale_list="${stale_list:+$stale_list, }${mods[$ci]} (1 commit behind)"
                        elif [ "$behind" -gt 1 ] 2>/dev/null; then
                            stale_list="${stale_list:+$stale_list, }${mods[$ci]} ($behind commits behind)"
                        fi
                        ci=$((ci + 1))
                    done
                    { printf '%s\n' "$key"; printf '%s\n' "$stale_list"; } > "$cache" 2>/dev/null
                fi
                emit '### Atlas freshness'
                if [ -z "$stale_list" ]; then
                    emit "All $checked atlas cards fresh."
                else
                    emit "STALE cards - consider /mem-sync: $stale_list"
                fi

                # ----- Recent activity: commits in the last 24h touching each card's paths -----
                # ONE repo-wide git log; each commit's file list is matched against every
                # card's pathspecs in bash. Omit the section entirely when nothing changed
                # (silence beats noise). Same silent-failure discipline.
                local rlog
                if rlog=$(git -C "$root" log --since=24.hours --format='%x40%x40' --name-only 2>/dev/null) \
                   && [ -n "$rlog" ]; then
                    local rcount=() rhit=() f
                    ci=0; while [ "$ci" -lt "$checked" ]; do rcount[$ci]=0; ci=$((ci + 1)); done
                    while IFS= read -r f; do
                        if [ "$f" = "@@" ]; then
                            ci=0; while [ "$ci" -lt "$checked" ]; do rhit[$ci]=0; ci=$((ci + 1)); done
                            continue
                        fi
                        [ -n "$f" ] || continue
                        ci=0
                        while [ "$ci" -lt "$checked" ]; do
                            if [ "${rhit[$ci]}" = 0 ]; then
                                while IFS= read -r p; do
                                    [ -n "$p" ] || continue
                                    if path_matches "$f" "$p"; then
                                        rhit[$ci]=1; rcount[$ci]=$((rcount[$ci] + 1)); break
                                    fi
                                done <<EOF_RP
${pathsets[$ci]}
EOF_RP
                            fi
                            ci=$((ci + 1))
                        done
                    done <<EOF_RLOG
$rlog
EOF_RLOG
                    local recent_line="" rn runit
                    ci=0
                    while [ "$ci" -lt "$checked" ]; do
                        rn=${rcount[$ci]}
                        if [ "$rn" -gt 0 ]; then
                            if [ "$rn" -eq 1 ]; then runit="commit"; else runit="commits"; fi
                            recent_line="${recent_line:+$recent_line, }${mods[$ci]} ($rn $runit)"
                        fi
                        ci=$((ci + 1))
                    done
                    if [ -n "$recent_line" ]; then
                        emit '### Recent activity (24h)'
                        emit "$recent_line"
                    fi
                fi
            fi
        fi

        # ----- Architecture overview: same frontmatter contract as a card -----
        local arch="$mem_dir/architecture.md"
        if [ -r "$arch" ] && parse_frontmatter "$arch" && [ -n "$FM_PATHS" ]; then
            local aarr=() ap abehind
            while IFS= read -r ap; do
                [ -n "$ap" ] && aarr+=("$ap")
            done <<EOF_APATHS
$FM_PATHS
EOF_APATHS
            case "$FM_VERIFIED" in
                ""|0000000*)
                    emit 'Architecture overview: no baseline - run /mem-arch update.' ;;
                *)
                    abehind=$(behind_count "$root" "$FM_VERIFIED" "${aarr[@]}")
                    if [ "$abehind" = "?" ]; then
                        emit 'Architecture overview: unknown baseline - run /mem-arch update.'
                    elif [ "$abehind" -eq 1 ] 2>/dev/null; then
                        emit 'Architecture overview: 1 commit behind - run /mem-arch update.'
                    elif [ "$abehind" -gt 1 ] 2>/dev/null; then
                        emit "Architecture overview: $abehind commits behind - run /mem-arch update."
                    fi ;;
            esac
        fi
    fi

    flush_and_exit
}

# Never let an error escape: stderr suppressed, exit code forced to 0.
main 2>/dev/null
exit 0
