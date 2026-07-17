#!/usr/bin/env bash
# engram-capture.sh -- Engram auto-capture hook (PreCompact + SessionEnd).
# Portable bash twin of engram-capture.ps1.
#
# Drafts a journal entry from the session transcript via headless Claude, then
# appends it to today's journal file. This is a best-effort SIDE EFFECT: every
# failure mode degrades silently and the script ALWAYS exits 0, so it can never
# break a session.
#
# LIMITATION: jq is NOT guaranteed to exist, so the flat string fields we need
# are extracted with grep/sed (same approach as engram-brief.sh). Any parse
# failure degrades to a silent exit 0.

# Model for the headless draft. Default: fast + cheap.
# Bump to a sonnet model (e.g. claude-sonnet-4-6) for richer drafts.
MODEL="claude-haiku-4-5"

main() {
    # ---------- re-entry guard (belt on top of --bare) ----------
    if [ "${ENGRAM_CAPTURE:-}" = "1" ]; then exit 0; fi

    # ---------- read stdin JSON ----------
    local raw event_name transcript_path cwd_val reason
    raw=$(cat 2>/dev/null) || raw=""
    event_name=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    transcript_path=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    cwd_val=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    reason=$(printf '%s' "$raw" | tr -d '\n' \
        | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    # JSON escapes backslashes; collapse '\\' -> '\' (Windows paths under Git Bash).
    transcript_path=${transcript_path//\\\\/\\}

    # ---------- resolve project root ----------
    local root="${CLAUDE_PROJECT_DIR:-}"
    [ -n "$root" ] || root="$cwd_val"
    [ -n "$root" ] || root="$PWD"
    root=${root//\\\\/\\}

    # ---------- guard: memory present and initialized ----------
    local mem_dir="$root/.claude/memory"
    local memory_md="$mem_dir/MEMORY.md"
    [ -f "$memory_md" ] || exit 0
    grep -q 'STATUS: EMPTY' "$memory_md" 2>/dev/null && exit 0

    # ---------- guard: transcript readable ----------
    [ -n "$transcript_path" ] || exit 0
    [ -r "$transcript_path" ] || exit 0

    local today
    today=$(date +%Y-%m-%d)

    # ---------- SessionEnd-only guards ----------
    # PreCompact implies a substantial session, so it has no heuristic.
    if [ "$event_name" = "SessionEnd" ]; then
        # Session continues later -> skip.
        [ "$reason" = "resume" ] && exit 0

        # Heuristic 1: trivial session (transcript under 80 KB).
        local bytes
        bytes=$(wc -c < "$transcript_path" 2>/dev/null | tr -d '[:space:]')
        [ -n "$bytes" ] || bytes=0
        if [ "$bytes" -lt 81920 ] 2>/dev/null; then exit 0; fi

        # Heuristic 2: today's journal already has an entry within the last 2 hours.
        local today_journal="$mem_dir/journal/$today.md"
        if [ -f "$today_journal" ]; then
            local last_hm eh em entry_min now_min diff
            last_hm=$(grep -Eo '^## [0-9][0-9]:[0-9][0-9]' "$today_journal" 2>/dev/null \
                | tail -1 | sed 's/^## //')
            if [ -n "$last_hm" ]; then
                eh=${last_hm%%:*}
                em=${last_hm##*:}
                entry_min=$((10#$eh * 60 + 10#$em))
                now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
                diff=$((now_min - entry_min))
                if [ "$diff" -ge 0 ] && [ "$diff" -lt 120 ]; then exit 0; fi
            fi
        fi
    fi

    # ---------- compose the extraction prompt ----------
    local now_hm
    now_hm=$(date +%H:%M)
    local prompt
    prompt="Read the Claude Code session transcript (JSONL) at this path:
$transcript_path
The file may be large. Read the tail portions that cover the actual work done in the session.

Decide whether anything DURABLE happened in this session: completed tasks, fixed bugs,
non-obvious learnings, dead ends, or decisions worth remembering later. If the session
was routine question-and-answer, exploration with no concrete outcome, or otherwise
trivial, output exactly this single word and nothing else:
SKIP

Otherwise output ONLY a journal entry in EXACTLY this format. No preamble, no code
fences, no trailing commentary -- only the entry:

## $now_hm — One-line headline of what happened [<your exact model id> · auto-draft]
- **Did:** what was accomplished, concretely -- wikilink the primary module(s) once, e.g. [[module-name]]
- **Learned:** non-obvious facts discovered (omit this whole line if none)
- **Dead ends:** what was tried and FAILED and why; mark each dead: or parked: (omit if none)
- **Touched:** files changed
- **Commits:** short commit shas this work produced (omit if none -- never invent a sha)
- **Next:** follow-ups worth filing (omit if none)
- **Note:** auto-captured from transcript (unreviewed) — verify before trusting

Hard rules:
- The headline time MUST be exactly $now_hm and the signature MUST end with · auto-draft].
- Sign the headline with your own exact model id.
- Keep the entry to 12 lines or fewer. Omit every field that has no content.
- Today's date is $today.
- Output the journal entry, or the single word SKIP. Nothing else."

    # ---------- spawn headless Claude ----------
    command -v claude >/dev/null 2>&1 || exit 0
    local output
    output=$(ENGRAM_CAPTURE=1 claude --bare -p "$prompt" --allowedTools "Read" --model "$MODEL" 2>/dev/null)
    [ $? -eq 0 ] || exit 0
    [ -n "$output" ] || exit 0

    # Strip leading blank lines.
    output=$(printf '%s' "$output" | sed '/./,$!d')
    [ -n "$output" ] || exit 0

    # ---------- validate ----------
    local first_line
    first_line=$(printf '%s\n' "$output" | sed -n '1p')
    case "$first_line" in
        '## '*) : ;;
        *) exit 0 ;;
    esac
    # Lenient on the dash: accept a hyphen or the em dash. LC_ALL=C -> byte match.
    printf '%s' "$first_line" \
        | LC_ALL=C grep -Eq '^## [0-9][0-9]:[0-9][0-9] (—|-) .+\[.+auto-draft\]' \
        || exit 0

    # ---------- append to today's journal (never overwrite) ----------
    local journal_dir="$mem_dir/journal"
    mkdir -p "$journal_dir" 2>/dev/null
    local journal_file="$journal_dir/$today.md"

    if [ ! -f "$journal_file" ]; then
        printf '# Journal — %s\n\n%s\n' "$today" "$output" > "$journal_file"
    else
        # Preserve all existing content; $(cat) strips only trailing newlines, so
        # the rewrite normalizes to exactly one blank line before the new entry.
        local existing
        existing=$(cat "$journal_file")
        printf '%s\n\n%s\n' "$existing" "$output" > "$journal_file.tmp" \
            && mv "$journal_file.tmp" "$journal_file"
    fi

    exit 0
}

# Never let an error escape: stderr suppressed, exit code forced to 0.
main 2>/dev/null
exit 0
