#!/usr/bin/env bash
# engram-lint.sh -- Engram deterministic memory linter (portable bash twin of engram-lint.ps1).
#
# Zero-token static checks over .claude/memory. Both scripts must emit byte-identical
# findings (same order, same messages) for identical inputs.
#
# Usage: engram-lint.sh [--root <repo>] [--json]
#   --root  repo root (default: current dir); memory is at <root>/.claude/memory
#   --json  emit a single-line JSON object CI can parse (stable schema)
#
# Exit code: 1 if any ERROR finding, else 0.
#
# Portability: bash 3.2 (no mapfile, no associative arrays), LF endings, jq not required.

# ---------- args ----------
ARG_ROOT="."
JSON=0
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ARG_ROOT="$2"; shift 2 ;;
        --json) JSON=1; shift ;;
        *)      shift ;;
    esac
done

# ---------- resolve + normalize root ----------
root=$(cd "$ARG_ROOT" 2>/dev/null && pwd)
[ -n "$root" ] || root="${ARG_ROOT%/}"
root="${root%/}"
mem_dir="$root/.claude/memory"
memory_md="$mem_dir/MEMORY.md"

TAB=$(printf '\t')

# ---------- findings store ----------
FINDINGS=()
ERRC=0
WARNC=0
INFOC=0

add_finding() {
    # $1 level  $2 check  $3 file  $4 message
    FINDINGS[${#FINDINGS[@]}]="$1$TAB$2$TAB$3$TAB$4"
    case "$1" in
        ERROR) ERRC=$((ERRC + 1)) ;;
        WARN)  WARNC=$((WARNC + 1)) ;;
        *)     INFOC=$((INFOC + 1)) ;;
    esac
}

count_lines() {
    # matches PS [IO.File]::ReadAllLines().Count
    if [ -f "$1" ]; then
        local n
        n=$(grep -c '' "$1" 2>/dev/null)
        [ -n "$n" ] || n=0
        printf '%s' "$n"
    else
        printf '0'
    fi
}

rel_path() {
    local f="${1//\\//}"
    case "$f" in
        "$root"/*) printf '%s' "${f#"$root"/}" ;;
        "$root")   printf '%s' "" ;;
        *)         printf '%s' "$f" ;;
    esac
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

emit_and_exit() {
    local i n rec level check file msg rest
    if [ "$JSON" -eq 1 ]; then
        local out
        out='{"errors":'"$ERRC"',"warnings":'"$WARNC"',"findings":['
        i=0; n=${#FINDINGS[@]}
        local first=1
        while [ "$i" -lt "$n" ]; do
            rec="${FINDINGS[$i]}"; i=$((i + 1))
            level="${rec%%$TAB*}"; rest="${rec#*$TAB}"
            check="${rest%%$TAB*}"; rest="${rest#*$TAB}"
            file="${rest%%$TAB*}"; msg="${rest#*$TAB}"
            [ "$first" -eq 1 ] || out="$out,"
            first=0
            out="$out{\"level\":\"$(json_escape "$level")\",\"check\":\"$(json_escape "$check")\",\"file\":\"$(json_escape "$file")\",\"message\":\"$(json_escape "$msg")\"}"
        done
        out="$out]}"
        printf '%s\n' "$out"
    else
        local use_color=0
        [ -t 1 ] && use_color=1
        local c_err='' c_warn='' c_info='' c_rst=''
        if [ "$use_color" -eq 1 ]; then
            c_err=$(printf '\033[31m'); c_warn=$(printf '\033[33m')
            c_info=$(printf '\033[36m'); c_rst=$(printf '\033[0m')
        fi
        local lvl col
        for lvl in ERROR WARN INFO; do
            i=0; n=${#FINDINGS[@]}
            while [ "$i" -lt "$n" ]; do
                rec="${FINDINGS[$i]}"; i=$((i + 1))
                level="${rec%%$TAB*}"; rest="${rec#*$TAB}"
                [ "$level" = "$lvl" ] || continue
                check="${rest%%$TAB*}"; rest="${rest#*$TAB}"
                file="${rest%%$TAB*}"; msg="${rest#*$TAB}"
                case "$lvl" in
                    ERROR) col="$c_err" ;;
                    WARN)  col="$c_warn" ;;
                    *)     col="$c_info" ;;
                esac
                printf '%s[%s] %s: %s - %s%s\n' "$col" "$level" "$check" "$file" "$msg" "$c_rst"
            done
        done
        printf 'Engram lint: %s error(s), %s warning(s), %s info\n' "$ERRC" "$WARNC" "$INFOC"
    fi
    if [ "$ERRC" -gt 0 ]; then exit 1; else exit 0; fi
}

resolve_link() {
    local t="$1" num
    [ -z "$t" ] && return 0
    case "$t" in
        adr-*)
            num="${t#adr-}"
            if printf '%s\n' "$TARGET_NAMES" | grep -qxF "$t"; then return 0; fi
            if printf '%s\n' "$TARGET_NAMES" | grep -q "^$num-"; then return 0; fi
            return 1
            ;;
    esac
    if printf '%s\n' "$TARGET_NAMES" | grep -qxF "$t"; then return 0; fi
    return 1
}

# ---------- guard: memory present? ----------
if [ ! -d "$mem_dir" ]; then
    add_finding INFO no-memory ".claude/memory" "no Engram memory found at .claude/memory"
    emit_and_exit
fi

# ---------- git detection ----------
is_git=0
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then is_git=1; fi

# ==========================================================================
# Checks run in a FIXED order; engram-lint.ps1 reproduces it exactly.
# ==========================================================================

# ---------- 1. no-git INFO ----------
if [ "$is_git" -eq 0 ]; then
    add_finding INFO no-git ".claude/memory" "not a git work tree; git-based checks skipped"
fi

# ---------- 2. version-drift ----------
mig_path="$root/.claude/skills/mem-sync/MIGRATIONS.md"
if [ ! -f "$mig_path" ]; then
    add_finding INFO version-drift ".claude/skills/mem-sync/MIGRATIONS.md" "MIGRATIONS.md not found; version-drift check skipped"
else
    cur_ver=$(sed -n 's/.*Current tooling version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$mig_path" | head -1)
    [ -n "$cur_ver" ] || cur_ver=0
    mem_ver=1
    if [ -f "$mem_dir/VERSION" ]; then
        v=$(tr -d '[:space:]' < "$mem_dir/VERSION")
        case "$v" in
            ''|*[!0-9]*) : ;;
            *) mem_ver="$v" ;;
        esac
    fi
    if [ "$cur_ver" -gt 0 ] 2>/dev/null && [ "$mem_ver" -lt "$cur_ver" ] 2>/dev/null; then
        add_finding WARN version-drift ".claude/memory/VERSION" "memory VERSION $mem_ver is behind current tooling version $cur_ver; run /mem-sync"
    fi
fi

# ---------- 3. MEMORY.md over-budget ----------
if [ -f "$memory_md" ]; then
    ml=$(count_lines "$memory_md")
    if [ "$ml" -gt 120 ] 2>/dev/null; then
        add_finding WARN over-budget ".claude/memory/MEMORY.md" "MEMORY.md is $ml lines (budget 120)"
    fi
fi

# ---------- enumerate atlas cards + index files (sorted by name) ----------
atlas_dir="$mem_dir/atlas"
card_files=()
index_files=()
if [ -d "$atlas_dir" ]; then
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        b=$(basename "$f")
        case "$b" in
            _*)      continue ;;
            INDEX-*) index_files[${#index_files[@]}]="$f" ;;
            *)       card_files[${#card_files[@]}]="$f" ;;
        esac
    done < <(ls -1 "$atlas_dir"/*.md 2>/dev/null | sort)
fi

# ---------- 4. per-card checks ----------
ci=0
while [ "$ci" -lt "${#card_files[@]}" ]; do
    card="${card_files[$ci]}"; ci=$((ci + 1))
    rel=$(rel_path "$card")

    has_fm=0
    if head -1 "$card" 2>/dev/null | grep -q '^---[[:space:]]*$'; then has_fm=1; fi
    fm=""
    if [ "$has_fm" -eq 1 ]; then
        fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$card")
    fi

    verified=$(printf '%s\n' "$fm" | sed -n 's/^verified:[[:space:]]*//p' | head -1 | awk '{print $1}')
    paths=$(printf '%s\n' "$fm" | awk '/^paths:[[:space:]]*$/{f=1;next}
        f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
            gsub(/^["'\'']|["'\'']$/,""); print; next}
        f{f=0}')
    fmc=$(printf '%s\n' "$fm" | grep -m1 '#' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    # paths -> array
    patharr=()
    while IFS= read -r p; do
        [ -n "$p" ] && patharr[${#patharr[@]}]="$p"
    done <<EOF
$paths
EOF

    # 4a. globs: brace-glob (string) / dead-glob (git)
    gi=0
    while [ "$gi" -lt "${#patharr[@]}" ]; do
        glob="${patharr[$gi]}"; gi=$((gi + 1))
        case "$glob" in
            *"{"*)
                add_finding ERROR brace-glob "$rel" "paths glob uses brace expansion (git matches nothing): $glob"
                continue
                ;;
        esac
        if [ "$is_git" -eq 1 ]; then
            ls_out=$(git -C "$root" ls-files -- "$glob" 2>/dev/null)
            if [ -z "$ls_out" ]; then
                add_finding ERROR dead-glob "$rel" "paths glob matches no tracked files: $glob"
            fi
        fi
    done

    # 4b. verified / stale
    if [ -z "$verified" ] || printf '%s' "$verified" | grep -qE '^0+$'; then
        disp="missing"
        [ -n "$verified" ] && disp="$verified"
        add_finding WARN unverified "$rel" "card is unverified (verified: $disp)"
    elif [ "$is_git" -eq 1 ]; then
        objt=$(git -C "$root" cat-file -t "$verified" 2>/dev/null)
        if [ "$objt" != "commit" ]; then
            add_finding ERROR bad-verified "$rel" "verified '$verified' is not a commit object"
        elif [ "${#patharr[@]}" -gt 0 ]; then
            loglines=$(git -C "$root" log --oneline "$verified..HEAD" -- "${patharr[@]}" 2>/dev/null)
            behind=$(printf '%s' "$loglines" | grep -c '.' 2>/dev/null)
            [ -n "$behind" ] || behind=0
            if [ "$behind" -gt 0 ] 2>/dev/null; then
                if [ "$behind" -eq 1 ]; then unit="commit"; else unit="commits"; fi
                add_finding WARN stale-card "$rel" "card is $behind $unit behind HEAD"
            fi
        fi
    fi

    # 4c. frontmatter-comment
    if [ -n "$fmc" ]; then
        add_finding WARN frontmatter-comment "$rel" "frontmatter line contains '#' (breaks parsers): $fmc"
    fi

    # 4d. card over-budget
    cl=$(count_lines "$card")
    if [ "$cl" -gt 60 ] 2>/dev/null; then
        add_finding WARN over-budget "$rel" "card is $cl lines (budget 60)"
    fi

    # 4e. dead-keyfile: first backtick token on each '- ' line inside '## Key files'
    kf_lines=$(awk '
        /^##[[:space:]]/ { if ($0 ~ /^##[[:space:]]+Key files[[:space:]]*$/) inkeys=1; else inkeys=0; next }
        inkeys && /^[[:space:]]*-[[:space:]]+`/ { print }
    ' "$card")
    if [ -n "$kf_lines" ]; then
        while IFS= read -r kl; do
            [ -n "$kl" ] || continue
            kf=$(printf '%s' "$kl" | sed -n 's/^[[:space:]]*-[[:space:]]*`\([^`]*\)`.*/\1/p')
            kf=$(printf '%s' "$kf" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            kf="${kf%/}"
            case "$kf" in *[*?{]*) continue ;; esac
            [ -n "$kf" ] || continue
            if [ ! -e "$root/$kf" ]; then
                add_finding ERROR dead-keyfile "$rel" "Key files path does not exist: $kf"
            fi
        done <<EOF
$kf_lines
EOF
    fi
done

# ---------- 5. INDEX-* over-budget ----------
ii=0
while [ "$ii" -lt "${#index_files[@]}" ]; do
    idx="${index_files[$ii]}"; ii=$((ii + 1))
    rel=$(rel_path "$idx")
    n=$(count_lines "$idx")
    if [ "$n" -gt 60 ] 2>/dev/null; then
        add_finding WARN over-budget "$rel" "index is $n lines (budget 60)"
    fi
done

# ---------- build wikilink target set + scan file list ----------
scan_files=()
TARGET_NAMES=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    b=$(basename "$f")
    case "$b" in _*) continue ;; esac
    scan_files[${#scan_files[@]}]="$f"
    bn="${b%.md}"
    TARGET_NAMES="$TARGET_NAMES$bn
"
done < <(find "$mem_dir" -type f -name '*.md' 2>/dev/null | sort)

# ---------- 6. broken-wikilink ----------
bt='`'
si=0
while [ "$si" -lt "${#scan_files[@]}" ]; do
    f="${scan_files[$si]}"; si=$((si + 1))
    rel=$(rel_path "$f")
    while IFS= read -r line || [ -n "$line" ]; do
        scan=$(printf '%s' "$line" | sed "s/$bt[^$bt]*$bt/ /g")
        links=$(printf '%s\n' "$scan" | grep -oE '\[\[[^]]+\]\]' 2>/dev/null)
        [ -n "$links" ] || continue
        while IFS= read -r lk; do
            [ -n "$lk" ] || continue
            inner=$(printf '%s' "$lk" | sed 's/^\[\[//; s/\]\]$//')
            target="${inner%%|*}"
            target="${target%%#*}"
            target=$(printf '%s' "$target" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            printf '%s' "$target" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._/-]*$' || continue
            if ! resolve_link "$target"; then
                add_finding ERROR broken-wikilink "$rel" "wikilink [[$target]] resolves to nothing"
            fi
        done <<EOF
$links
EOF
    done < "$f"
done

# ---------- 7. unsigned-entry (journal/YYYY-MM-DD.md headlines) ----------
journal_dir="$mem_dir/journal"
if [ -d "$journal_dir" ]; then
    while IFS= read -r j; do
        [ -n "$j" ] || continue
        rel=$(rel_path "$j")
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                '## '*)
                    trim=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
                    if printf '%s' "$trim" | grep -qE '\[[^]]+\][[:space:]]*$'; then
                        :
                    else
                        add_finding INFO unsigned-entry "$rel" "journal headline lacks [model-id] signature: $trim"
                    fi
                    ;;
            esac
        done < "$j"
    done < <(ls -1 "$journal_dir"/*.md 2>/dev/null | grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' | sort)
fi

emit_and_exit
