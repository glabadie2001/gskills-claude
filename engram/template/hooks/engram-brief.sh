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

    # ----- Atlas freshness: footprint-manifest set-compare (engram-manifest twin) -----
    # One script call (3 git spawns inside) replaces the old per-card `git log`
    # loop. States: VERIFIED = trust the card; DRIFTED = trust minus the listed
    # delta files; ASSUMED = never verified (map, not truth); DIRTY = uncommitted
    # edits touch card footprints (designed state -- manifests see commits only).
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local atlas_dir="$mem_dir/atlas" cards
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
        # Omit the section entirely when nothing changed (silence beats noise).
        cards=$(ls -1 "$atlas_dir"/*.md 2>/dev/null | grep -v '/_[^/]*$')
        if [ -n "$cards" ]; then
            local recent_line="" card fm rmod rpaths rn runit
            while IFS= read -r card; do
                [ -r "$card" ] || continue
                # Frontmatter = lines between the first pair of '---' fences.
                head -1 "$card" | grep -q '^---[[:space:]]*$' || continue
                fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$card")
                rmod=$(printf '%s\n' "$fm" | sed -n 's/^module:[[:space:]]*//p' | head -1 \
                    | sed 's/[[:space:]]*$//')
                rpaths=$(printf '%s\n' "$fm" \
                    | awk '/^paths:[[:space:]]*$/{f=1;next}
                           f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
                               gsub(/^["'\'']|["'\'']$/,""); print; next}
                           f{f=0}')
                [ -n "$rmod" ] || rmod=$(basename "$card" .md)
                [ -n "$rpaths" ] || continue    # malformed card: skip silently
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
            done <<EOF_CARDS
$cards
EOF_CARDS
            if [ -n "$recent_line" ]; then
                emit '### Recent activity (24h)'
                emit "$recent_line"
            fi
        fi

        # ----- Architecture overview: same frontmatter contract as a card -----
        local arch="$mem_dir/architecture.md"
        if [ -r "$arch" ] && head -1 "$arch" | grep -q '^---[[:space:]]*$'; then
            local afm averified apaths
            afm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$arch")
            averified=$(printf '%s\n' "$afm" | sed -n 's/^verified:[[:space:]]*//p' | head -1 \
                | awk '{print $1}')
            apaths=$(printf '%s\n' "$afm" \
                | awk '/^paths:[[:space:]]*$/{f=1;next}
                       f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
                           gsub(/^["'\'']|["'\'']$/,""); print; next}
                       f{f=0}')
            if [ -n "$apaths" ]; then
                local aarr=() ap abehind
                while IFS= read -r ap; do
                    [ -n "$ap" ] && aarr+=("$ap")
                done <<EOF_APATHS
$apaths
EOF_APATHS
                case "$averified" in
                    ""|0000000*)
                        emit 'Architecture overview: no baseline - run /mem-arch update.' ;;
                    *)
                        if [ "$(git -C "$root" cat-file -t "$averified" 2>/dev/null)" != "commit" ]; then
                            emit 'Architecture overview: unknown baseline - run /mem-arch update.'
                        else
                            abehind=$(git -C "$root" log --oneline "$averified..HEAD" -- "${aarr[@]}" 2>/dev/null | grep -c .)
                            [ -n "$abehind" ] || abehind=0
                            if [ "$abehind" -eq 1 ] 2>/dev/null; then
                                emit 'Architecture overview: 1 commit behind - run /mem-arch update.'
                            elif [ "$abehind" -gt 1 ] 2>/dev/null; then
                                emit "Architecture overview: $abehind commits behind - run /mem-arch update."
                            fi
                        fi ;;
                esac
            fi
        fi
    fi

    flush_and_exit
}

# Never let an error escape: stderr suppressed, exit code forced to 0.
main 2>/dev/null
exit 0
