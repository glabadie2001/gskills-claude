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

# Windows (Git Bash/MSYS): process spawns can cost ~1s each there, which blows
# the 30s hook timeout. Hand off to the PowerShell twin, which does the same
# work in seconds. The committed settings.json stays cross-platform ("shell":
# "bash" everywhere); this dispatch is the per-OS branch. Kept spawn-free
# except cygpath + the exec itself; falls through to bash if anything is off.
case "${OSTYPE:-}" in
    msys*|cygwin*)
        _psf="${0%/*}/engram-brief.ps1"
        if [ -f "$_psf" ] && command -v powershell.exe >/dev/null 2>&1; then
            command -v cygpath >/dev/null 2>&1 && _psf=$(cygpath -w "$_psf")
            exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$_psf"
        fi ;;
esac

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

    # ---------- locate the Engram memory (root itself, then pin file, then one
    # level down) ----------
    # Nested: Claude launched in a PARENT of the Engram-fied repo -> a pin file
    # (.claude/engram-root, written by the installer) or a one-level-down probe
    # (statusline's algorithm) resolves the child; sub_label tags the brief
    # header so it's clear which project this is. An invalid/dangling pin falls
    # through to the probe rather than failing hard.
    local sub_label=""
    if [ ! -f "$root/.claude/memory/MEMORY.md" ]; then
        local pin_file="$root/.claude/engram-root" pin_line="" pl
        if [ -f "$pin_file" ]; then
            while IFS= read -r pl || [ -n "$pl" ]; do
                pl=${pl%$'\r'}
                pl=$(printf '%s' "$pl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                [ -n "$pl" ] && { pin_line="$pl"; break; }
            done < "$pin_file"
        fi
        if [ -n "$pin_line" ] && [ -f "$root/$pin_line/.claude/memory/MEMORY.md" ]; then
            root="$root/$pin_line"
            sub_label=$(basename "$root")
        else
            local m first=""
            for m in "$root"/*/.claude/memory/MEMORY.md; do
                [ -f "$m" ] || continue
                [ -n "$first" ] || first="$m"
            done
            if [ -n "$first" ]; then
                root=${first%/.claude/memory/MEMORY.md}
                sub_label=$(basename "$root")
            fi
        fi
    fi

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
    local brief_header='## Engram session brief'
    [ -n "$sub_label" ] && brief_header="$brief_header ($sub_label)"
    emit "$brief_header"
    emit 'Details live in .claude/memory/ (MEMORY.md is the index).'
    emit ''

    local memory_empty=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *'STATUS: EMPTY'*) memory_empty=1; break ;; esac
    done < "$memory_md"

    # ----- Tasks: top-level bullets of ## Now and ## Next (cap 12 lines) -----
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
                        [ "${#task_lines[@]}" -lt 12 ] && task_lines+=("$line")
                    else
                        in_wanted=0
                    fi
                    ;;
                *)
                    # Top-level bullets only; continuation lines stay in tasks.md.
                    case "$line" in '- '*|'* '*) ;; *) continue ;; esac
                    if [ "$in_wanted" = 1 ] && [ "${#task_lines[@]}" -lt 12 ]; then
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
        emit '(Lines clipped - read tasks.md for detail.)'
        emit ''
    fi

    if [ "$memory_empty" = 1 ]; then
        emit 'Memory is empty - run /mem-init to bootstrap it from the codebase.'
        flush_and_exit
    fi

    # ----- Recent journal: headlines of the last 3 entries in the 2 newest files -----
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
        local budget=10 ji=$((jn - 1)) jstop=$((jn - 2))
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
                # Headlines only; the bodies stay in the journal file.
                local from=0
                [ "$ns" -gt 3 ] && from=$((ns - 3))
                while [ "$from" -lt "$ns" ] && [ "$budget" -gt 0 ]; do
                    emit "${jl[${starts[$from]}]}"; budget=$((budget - 1))
                    from=$((from + 1))
                done
            fi
                    i=$((i + 1))
                done
            fi
        done
    fi
    emit ''

    # ----- Atlas freshness: footprint-manifest set-compare (engram-manifest twin) -----
    # One script call (3 git spawns inside) replaces the old per-card `git log`
    # loop. States: VERIFIED = trust the card; DRIFTED = trust minus the listed
    # delta files; ASSUMED = never verified (map, not truth); DIRTY = uncommitted
    # edits touch card footprints (designed state -- manifests see commits only).
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local atlas_dir="$mem_dir/atlas" cards=() card
        for card in "$atlas_dir"/*.md; do
            [ -f "$card" ] || continue
            case "${card##*/}" in _*) continue ;; esac
            cards+=("$card")
        done
        local mscript="$root/.claude/scripts/engram-manifest.sh" mstatus=""
        if [ -f "$mscript" ]; then
            mstatus=$(bash "$mscript" status --root "$root" 2>/dev/null)
            if [ -n "$mstatus" ]; then
                local n_total=0 n_verified=0 drift_list="" assumed_list="" dirty_detail=""
                local st mod det
                while IFS=$'\t' read -r st mod det; do
                    case "$st" in
                        VERIFIED)   n_total=$((n_total + 1)); n_verified=$((n_verified + 1)) ;;
                        DRIFTED|NOMANIFEST)
                                    n_total=$((n_total + 1))
                                    drift_list="${drift_list:+$drift_list, }$mod ($det)" ;;
                        ASSUMED)    n_total=$((n_total + 1))
                                    assumed_list="${assumed_list:+$assumed_list, }$mod" ;;
                        DIRTY)      dirty_detail="$det" ;;
                    esac
                done <<EOF_MSTATUS
$mstatus
EOF_MSTATUS
                if [ "$n_total" -gt 0 ]; then
                    emit '### Atlas freshness'
                    if [ -z "$drift_list" ] && [ -z "$assumed_list" ]; then
                        emit "All $n_total atlas cards VERIFIED."
                    else
                        [ -n "$drift_list" ] && emit "DRIFTED - consider /mem-sync: $drift_list"
                        [ -n "$assumed_list" ] && emit "ASSUMED (never verified; map, not truth): $assumed_list"
                    fi
                    [ -n "$dirty_detail" ] && emit "Uncommitted (manifests see commits only): $dirty_detail"
                fi
            fi
        else
            emit '### Atlas freshness'
            emit 'Unavailable - engram-manifest script missing; refresh Engram tooling (installer -RefreshTooling).'
        fi

        # ----- Recent activity: commits in the last 24h touching each card's paths -----
        # ONE repo-wide git log; each commit's file list is matched against every
        # card's pathspecs in bash. Omit the section entirely when nothing changed
        # (silence beats noise). Same silent-failure discipline.
        if [ "${#cards[@]}" -gt 0 ]; then
            # Parse every card once (pure bash). Parallel arrays: module + paths.
            local mods=() pathsets=() checked=0 ci
            for card in "${cards[@]}"; do
                [ -r "$card" ] || continue
                parse_frontmatter "$card" || continue
                [ -n "$FM_PATHS" ] || continue    # malformed card: skip silently
                local module="$FM_MODULE"
                [ -n "$module" ] || { module="${card##*/}"; module="${module%.md}"; }
                mods+=("$module")
                pathsets+=("$FM_PATHS")
                checked=$((checked + 1))
            done
            if [ "$checked" -gt 0 ]; then
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
