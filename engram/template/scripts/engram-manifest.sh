#!/usr/bin/env bash
# engram-manifest.sh -- Engram footprint-manifest tool (portable bash twin of
# engram-manifest.ps1). Both twins must emit byte-identical output for identical
# inputs.
#
# A card's manifest (atlas/<module>.manifest) is the set of tracked files under
# the card's `paths:` globs AT THE COMMIT the card was last verified against
# (frontmatter `verified:`): one "<40-hex blob sha> <path>" line per file,
# LC_ALL=C sorted by path, LF endings. Manifests are SCRIPT-GENERATED ONLY (the
# linter recomputes them and ERRORs on any mismatch) and state only COMMITTED
# content: they are written from `git ls-tree -r <verified>`, never from the
# working tree -- so a manifest can never vouch for code that isn't in a commit.
#
# Usage: engram-manifest.sh <status|update> [--root <repo>] [--card <module>]...
#
#   status   one line per atlas card:  STATE<TAB>module<TAB>detail
#     VERIFIED    manifest matches the tracked tree at HEAD (content-addressed:
#                 a revert back to verified content counts as current)
#     DRIFTED     footprint changed since attestation: "N changed, N added, N removed"
#     ASSUMED     never verified (verified missing/0000000) -- map, not truth
#     NOMANIFEST  attested but no manifest sidecar yet (pre-migration):
#                 "N commits behind" | "no manifest yet" | "unknown baseline"
#     plus, only when uncommitted changes touch at least one card footprint,
#     one final aggregate line (a designed, lint-clean state):
#     DIRTY<TAB>-<TAB>"N files across N cards"   (diff vs HEAD + untracked)
#
#   update   (re)write each attested card's manifest from git ls-tree at its
#            own `verified` sha; never touches ASSUMED cards. Prints one line
#            per card: WROTE (files written) | OK (unchanged) | SKIP (no/bad
#            baseline); full runs also PRUNE manifests whose card is gone.
#
# Spawn budget: status costs 3 git calls total (rev-parse, ls-tree -r HEAD,
# status --porcelain) plus sed/awk per card; per-card git calls happen only for
# NOMANIFEST fallbacks and in update mode. Glob matching is done in-process with
# git-default pathspec semantics (* and ** match across '/'); exotic pathspec
# magic is unsupported.
#
# Portability: bash 3.2 (no mapfile, no associative arrays), LF endings, no jq.

# Windows (Git Bash/MSYS): hand off to the PowerShell twin (process spawns cost
# ~1s each under Git Bash; the .ps1 does the same work in-process).
case "${OSTYPE:-}" in
    msys*|cygwin*)
        _psf="${0%/*}/engram-manifest.ps1"
        if [ -f "$_psf" ] && command -v powershell.exe >/dev/null 2>&1; then
            command -v cygpath >/dev/null 2>&1 && _psf=$(cygpath -w "$_psf")
            exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$_psf" "$@"
        fi ;;
esac

# ---------- args ----------
MODE=""
ARG_ROOT="."
ONLY_CARDS=""
while [ $# -gt 0 ]; do
    case "$1" in
        status|update) MODE="$1"; shift ;;
        --root) ARG_ROOT="$2"; shift 2 ;;
        --card) ONLY_CARDS="$ONLY_CARDS$2
"; shift 2 ;;
        *) shift ;;
    esac
done
if [ "$MODE" != "status" ] && [ "$MODE" != "update" ]; then
    printf 'usage: engram-manifest.sh <status|update> [--root <repo>] [--card <module>]...\n' >&2
    exit 2
fi

# ---------- resolve + normalize root (same pin/probe order as the linter) ----------
root=$(cd "$ARG_ROOT" 2>/dev/null && pwd)
[ -n "$root" ] || root="${ARG_ROOT%/}"
root="${root%/}"
if [ ! -f "$root/.claude/memory/MEMORY.md" ]; then
    resolved=""
    pin_path="$root/.claude/engram-root"
    if [ -f "$pin_path" ]; then
        pin_line=""
        while IFS= read -r pl || [ -n "$pl" ]; do
            pl="${pl%$'\r'}"
            pl=$(printf '%s' "$pl" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
            if [ -n "$pl" ]; then pin_line="$pl"; break; fi
        done < "$pin_path"
        if [ -n "$pin_line" ]; then
            cand="${root}/${pin_line}"
            cand="${cand%/}"
            [ -f "$cand/.claude/memory/MEMORY.md" ] && resolved="$cand"
        fi
    fi
    if [ -z "$resolved" ]; then
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            cand="${d%/}"
            if [ -f "$cand/.claude/memory/MEMORY.md" ]; then
                resolved="$cand"
                break
            fi
        done < <(ls -1d "$root"/*/ 2>/dev/null | sort)
    fi
    [ -n "$resolved" ] && root="$resolved"
fi

atlas_dir="$root/.claude/memory/atlas"
[ -d "$atlas_dir" ] || exit 1
git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 1

# ---------- enumerate cards (sorted; skip _*.md templates and INDEX-*.md) ----------
card_files=()
while IFS= read -r f; do
    [ -n "$f" ] || continue
    b=$(basename "$f")
    case "$b" in
        _*|INDEX-*) continue ;;
    esac
    card_files[${#card_files[@]}]="$f"
done < <(ls -1 "$atlas_dir"/*.md 2>/dev/null | LC_ALL=C sort)

# ---------- helpers ----------
parse_card() {
    # $1 = card path -> sets MODULE, VERIFIED, PATHARR[]
    local card="$1" fm
    MODULE=$(basename "$card" .md)
    VERIFIED=""
    PATHARR=()
    head -1 "$card" 2>/dev/null | grep -q '^---[[:space:]]*$' || return 0
    fm=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$card")
    VERIFIED=$(printf '%s\n' "$fm" | sed -n 's/^verified:[[:space:]]*//p' | head -1 | awk '{print $1}')
    local paths p
    paths=$(printf '%s\n' "$fm" | awk '/^paths:[[:space:]]*$/{f=1;next}
        f && /^[[:space:]]+-[[:space:]]*/{sub(/^[[:space:]]+-[[:space:]]*/,"");
            gsub(/^["'\'']|["'\'']$/,""); print; next}
        f{f=0}')
    while IFS= read -r p; do
        [ -n "$p" ] && PATHARR[${#PATHARR[@]}]="$p"
    done <<EOF
$paths
EOF
}

globs_to_re() {
    # PATHARR[] -> one ERE matching git-default pathspec semantics:
    # * and ? match across '/', a wildcard-free glob also matches as a dir prefix.
    local re="" g i c out
    for g in "${PATHARR[@]}"; do
        out=""
        i=0
        while [ "$i" -lt "${#g}" ]; do
            c="${g:$i:1}"
            case "$c" in
                '*') out="$out.*" ;;
                '?') out="$out." ;;
                '.'|'+'|'('|')'|'|'|'^'|'$'|'{'|'}'|'\')
                     out="$out\\$c" ;;
                *)   out="$out$c" ;;
            esac
            i=$((i + 1))
        done
        re="${re:+$re|}$out"
    done
    [ -n "$re" ] && printf '^(%s)(/.*)?$' "$re"
}

is_attested() {
    # $1 = verified value; 0 = attested (non-empty, not all zeros)
    case "$1" in
        ""|0000000*) return 1 ;;
        *) return 0 ;;
    esac
}

card_selected() {
    # $1 = module; true when no --card filter or module listed
    [ -z "$ONLY_CARDS" ] && return 0
    printf '%s' "$ONLY_CARDS" | grep -qxF "$1"
}

plural() {
    # $1 count  $2 singular  $3 plural
    if [ "$1" -eq 1 ] 2>/dev/null; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "$3"; fi
}

manifest_lines_at() {
    # $1 = commit sha, $2 = footprint regex. Emits "sha path" lines, LC_ALL=C
    # path order. ls-tree path arguments are literal prefixes, NOT pathspec
    # globs -- so list the whole tree and filter with the same in-process
    # matcher status uses (identical semantics by construction).
    git -C "$root" -c core.quotepath=false ls-tree -r "$1" 2>/dev/null \
        | ENGRAM_RE="$2" awk '
            BEGIN { re=ENVIRON["ENGRAM_RE"] }
            { i=index($0,"\t"); if (i==0) next
              meta=substr($0,1,i-1); n=split(meta,a," "); if (n<3) next
              p=substr($0,i+1)
              if (p ~ re) print a[3]" "p }' \
        | LC_ALL=C sort -t' ' -k2
}

# ==========================================================================
# status
# ==========================================================================
if [ "$MODE" = "status" ]; then
    head_tree=$(git -C "$root" -c core.quotepath=false ls-tree -r HEAD 2>/dev/null)
    porcelain=$(git -C "$root" -c core.quotepath=false status --porcelain 2>/dev/null)

    # Uncommitted paths (staged, unstaged, untracked); renames keep the new name.
    dirty_paths=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        p="${line:3}"
        case "$p" in
            *' -> '*) p="${p##* -> }" ;;
        esac
        p="${p%\"}"
        p="${p#\"}"
        [ -n "$p" ] && dirty_paths="$dirty_paths$p
"
    done <<EOF_PORC
$porcelain
EOF_PORC

    dirty_files=""
    dirty_cards=0

    ci=0
    while [ "$ci" -lt "${#card_files[@]}" ]; do
        card="${card_files[$ci]}"; ci=$((ci + 1))
        parse_card "$card"
        [ "${#PATHARR[@]}" -gt 0 ] || continue    # malformed card: skip silently
        re=$(globs_to_re)
        mf="$atlas_dir/$MODULE.manifest"

        # Dirty scan for this footprint (state-independent aggregate).
        card_dirty=""
        if [ -n "$dirty_paths" ]; then
            # Regex via ENVIRON: awk -v would reprocess backslash escapes.
            card_dirty=$(printf '%s' "$dirty_paths" | ENGRAM_RE="$re" awk '
                BEGIN { re=ENVIRON["ENGRAM_RE"] }
                $0 ~ re { print }')
        fi
        if [ -n "$card_dirty" ]; then
            dirty_cards=$((dirty_cards + 1))
            dirty_files="$dirty_files$card_dirty
"
        fi

        if ! is_attested "$VERIFIED"; then
            printf 'ASSUMED\t%s\tnever verified\n' "$MODULE"
            continue
        fi

        if [ ! -f "$mf" ]; then
            # Transitional: attested card, no sidecar -- fall back to the range check.
            if [ "$(git -C "$root" cat-file -t "$VERIFIED" 2>/dev/null)" != "commit" ]; then
                printf 'NOMANIFEST\t%s\tunknown baseline\n' "$MODULE"
            else
                behind=$(git -C "$root" log --oneline "$VERIFIED..HEAD" -- "${PATHARR[@]}" 2>/dev/null | grep -c .)
                [ -n "$behind" ] || behind=0
                if [ "$behind" -gt 0 ] 2>/dev/null; then
                    printf 'NOMANIFEST\t%s\t%s behind\n' "$MODULE" "$(plural "$behind" commit commits)"
                else
                    printf 'NOMANIFEST\t%s\tno manifest yet\n' "$MODULE"
                fi
            fi
            continue
        fi

        # Set-compare: manifest (footprint at attestation) vs tracked tree at HEAD.
        counts=$({ sed 's/^/M /' "$mf" 2>/dev/null
                   printf '%s\n' "$head_tree" | sed 's/^/T /'
                 } | ENGRAM_RE="$re" awk '
            BEGIN { re=ENVIRON["ENGRAM_RE"] }
            /^M / { s=substr($0,3); if (length(s)>=42) man[substr(s,42)]=substr(s,1,40); next }
            /^T / { t=substr($0,3); i=index(t,"\t"); if (i==0) next
                    meta=t; sub(/\t.*/,"",meta); n=split(meta,a," "); if (n<3) next
                    p=substr(t,i+1)
                    if (p ~ re) cur[p]=a[3] }
            END { c=0; ad=0; r=0
                  for (p in man) { if (!(p in cur)) r++; else if (man[p]!=cur[p]) c++ }
                  for (p in cur) if (!(p in man)) ad++
                  print c" "ad" "r }')
        chg=${counts%% *}; rest=${counts#* }; add=${rest%% *}; rem=${rest##* }
        if [ "$((chg + add + rem))" -eq 0 ] 2>/dev/null; then
            printf 'VERIFIED\t%s\t-\n' "$MODULE"
        else
            detail=""
            [ "$chg" -gt 0 ] 2>/dev/null && detail="$chg changed"
            [ "$add" -gt 0 ] 2>/dev/null && detail="${detail:+$detail, }$add added"
            [ "$rem" -gt 0 ] 2>/dev/null && detail="${detail:+$detail, }$rem removed"
            printf 'DRIFTED\t%s\t%s\n' "$MODULE" "$detail"
        fi
    done

    if [ "$dirty_cards" -gt 0 ]; then
        n_dirty=$(printf '%s' "$dirty_files" | LC_ALL=C sort -u | grep -c .)
        printf 'DIRTY\t-\t%s across %s\n' \
            "$(plural "$n_dirty" file files)" "$(plural "$dirty_cards" card cards)"
    fi
    exit 0
fi

# ==========================================================================
# update
# ==========================================================================
ci=0
while [ "$ci" -lt "${#card_files[@]}" ]; do
    card="${card_files[$ci]}"; ci=$((ci + 1))
    parse_card "$card"
    card_selected "$MODULE" || continue
    [ "${#PATHARR[@]}" -gt 0 ] || continue    # malformed card: skip silently
    re=$(globs_to_re)
    mf="$atlas_dir/$MODULE.manifest"

    if ! is_attested "$VERIFIED"; then
        printf 'SKIP\t%s\tnever verified\n' "$MODULE"
        continue
    fi
    if [ "$(git -C "$root" cat-file -t "$VERIFIED" 2>/dev/null)" != "commit" ]; then
        printf 'SKIP\t%s\tbad verified: %s\n' "$MODULE" "$VERIFIED"
        continue
    fi

    new_content=$(manifest_lines_at "$VERIFIED" "$re")
    old_content=""
    [ -f "$mf" ] && old_content=$(cat "$mf" 2>/dev/null)
    if [ -f "$mf" ] && [ "$new_content" = "$old_content" ]; then
        printf 'OK\t%s\tunchanged\n' "$MODULE"
        continue
    fi
    if [ -n "$new_content" ]; then
        printf '%s\n' "$new_content" > "$mf"
        n=$(printf '%s\n' "$new_content" | grep -c .)
    else
        : > "$mf"
        n=0
    fi
    printf 'WROTE\t%s\t%s\n' "$MODULE" "$(plural "$n" file files)"
done

# Orphan manifests (card deleted): prune only on full runs.
if [ -z "$ONLY_CARDS" ]; then
    while IFS= read -r mf; do
        [ -n "$mf" ] || continue
        b=$(basename "$mf" .manifest)
        if [ ! -f "$atlas_dir/$b.md" ]; then
            rm -f "$mf" 2>/dev/null
            printf 'PRUNE\t%s\tno card\n' "$b"
        fi
    done < <(ls -1 "$atlas_dir"/*.manifest 2>/dev/null | LC_ALL=C sort)
fi
exit 0
