#!/usr/bin/env bash
# install.sh -- Install the Engram memory engine into a target project (bash twin of install.ps1).
#
# Usage:
#   ./install.sh --target /path/to/project [--refresh-tooling] [--modules bug-sweep]
#   ./install.sh /path/to/project
#
# --modules applies opt-in modules (see modules/README.md): additive and
# idempotent, so it also works on an EXISTING install (memory otherwise
# untouched; without --refresh-tooling, tooling is untouched too).
#
# Settings merge strategy: uses jq when available. Without jq, an EXISTING
# settings.json is never touched (manual-merge instructions are printed
# instead of risking corruption); a missing settings.json is written directly.

set -u

# ---------- args ----------
target=""
refresh=0
autocapture=0
modules=""
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--target|-Target)
            [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
            target="$2"; shift 2 ;;
        --refresh-tooling|-RefreshTooling)
            refresh=1; shift ;;
        --auto-capture|-AutoCapture)
            autocapture=1; shift ;;
        -m|--modules|-Modules)
            [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
            modules="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: install.sh --target <path> [--refresh-tooling] [--auto-capture] [--modules bug-sweep[,name2]]"; exit 0 ;;
        -*)
            echo "ERROR: unknown option: $1" >&2; exit 1 ;;
        *)
            if [ -z "$target" ]; then target="$1"; else
                echo "ERROR: unexpected argument: $1" >&2; exit 1
            fi
            shift ;;
    esac
done
if [ -z "$target" ]; then
    echo "ERROR: -Target <path> is mandatory. Usage: install.sh --target <path> [--refresh-tooling]" >&2
    exit 1
fi

# ---------- resolve paths ----------
engine_root=$(cd "$(dirname "$0")" && pwd)
template_dir="$engine_root/template"
if [ ! -d "$template_dir" ]; then
    echo "ERROR: template directory not found at $template_dir" >&2
    exit 1
fi
if [ ! -d "$target" ]; then
    echo "ERROR: target directory does not exist: $target" >&2
    exit 1
fi
target=$(cd "$target" && pwd)

echo "Engram installer"
echo "  engine: $engine_root"
echo "  target: $target"
echo ""

# ---------- git check (warn only) ----------
if [ ! -e "$target/.git" ]; then
    echo "WARNING: target is not a git repo: staleness tracking will be disabled until git init." >&2
fi

claude_dir="$target/.claude"
mem_target="$claude_dir/memory"
skills_target="$claude_dir/skills"
hooks_target="$claude_dir/hooks"
settings_path="$claude_dir/settings.json"

# ---------- modules: applier (see modules/README.md) ----------
# Copy a module's memory fragment without ever clobbering existing paths,
# then add its MEMORY.md bullets if absent. Additive + idempotent.
install_module() {
    local name="$1" mod_dir="$engine_root/modules/$1"
    local added=0 kept=0 rel dest snip memory_md marker tmp f d
    if [ ! -d "$mod_dir" ]; then
        echo "WARNING: module '$name' not found under modules/ - skipped." >&2
        return
    fi
    if [ -d "$mod_dir/memory" ]; then
        while IFS= read -r d; do
            rel="${d#"$mod_dir/memory"}"; rel="${rel#/}"
            [ -n "$rel" ] && mkdir -p "$mem_target/$rel"
        done < <(find "$mod_dir/memory" -type d | sort)
        while IFS= read -r f; do
            rel="${f#"$mod_dir/memory/"}"
            dest="$mem_target/$rel"
            if [ -e "$dest" ]; then kept=$((kept + 1)); continue; fi
            mkdir -p "$(dirname "$dest")"
            cp "$f" "$dest"
            added=$((added + 1))
        done < <(find "$mod_dir/memory" -type f | sort)
    fi
    echo "  - module $name: $added file(s) added, $kept already present (never clobbered)."
    snip="$mod_dir/MEMORY-snippet.md"
    memory_md="$mem_target/MEMORY.md"
    if [ -f "$snip" ] && [ -f "$memory_md" ]; then
        marker=$(grep -oE '\]\([^)[:space:]]+\)' "$snip" 2>/dev/null | head -1 | sed 's/^](//; s/)$//')
        if [ -n "$marker" ] && grep -qF "$marker" "$memory_md" 2>/dev/null; then
            echo "  - module $name: MEMORY.md bullets already present - unchanged."
        else
            tmp=$(mktemp)
            awk -v snipfile="$snip" '
                { L[NR] = $0 }
                END {
                    s = 0
                    for (i = 1; i <= NR; i++) if (L[i] ~ /^Skills:/) { s = i; break }
                    if (s == 0) {
                        for (i = 1; i <= NR; i++) print L[i]
                        print ""
                        while ((getline line < snipfile) > 0) print line
                    } else {
                        e = s - 1
                        while (e >= 1 && L[e] ~ /^[[:space:]]*$/) e--
                        for (i = 1; i <= e; i++) print L[i]
                        while ((getline line < snipfile) > 0) print line
                        print ""
                        for (i = s; i <= NR; i++) print L[i]
                    }
                }' "$memory_md" > "$tmp" && mv "$tmp" "$memory_md"
            echo "  - module $name: MEMORY.md 'Where everything lives' bullets added."
        fi
    fi
}

apply_modules() {
    local m
    for m in $(printf '%s' "$modules" | tr ',' ' '); do
        install_module "$m"
    done
}

# ---------- never clobber memory ----------
memory_present=0
[ -f "$mem_target/MEMORY.md" ] && memory_present=1
if [ "$memory_present" = 1 ] && [ "$refresh" != 1 ]; then
    if [ -n "$modules" ]; then
        # Module-only application onto an existing install: memory is only
        # ever ADDED to (the applier never clobbers), tooling untouched.
        echo "  - memory present - applying module(s) only; tooling untouched."
        apply_modules
        echo ""
        echo "Module application complete. Memory and tooling otherwise untouched."
        exit 0
    fi
    echo "Engram already installed (memory present) - refusing to touch .claude/memory. Use --refresh-tooling to update skills/hooks only, or --modules <name> to add a module."
    exit 0
fi

mkdir -p "$claude_dir"

# ---------- 1. memory ----------
if [ "$memory_present" = 1 ]; then
    echo "  - memory: present - left untouched (refresh-tooling mode)."
else
    mkdir -p "$mem_target"
    cp -R "$template_dir/memory/." "$mem_target/"
    # Ensure expected directories exist; drop .gitkeep in any that end up empty.
    for sub in atlas journal journal/archive decisions; do
        mkdir -p "$mem_target/$sub"
        if [ -z "$(ls -A "$mem_target/$sub" 2>/dev/null)" ]; then
            : > "$mem_target/$sub/.gitkeep"
        fi
    done
    echo "  - memory: copied template to .claude/memory/"
fi

# ---------- 2. skills (tooling: overwrite allowed) ----------
skills_source="$template_dir/skills"
if [ -d "$skills_source" ] && [ -n "$(ls -A "$skills_source" 2>/dev/null)" ]; then
    note=""
    [ -d "$skills_target" ] && note=" (existing files overwritten)"
    mkdir -p "$skills_target"
    cp -R "$skills_source/." "$skills_target/"
    echo "  - skills: copied to .claude/skills/$note"
else
    echo "WARNING: template/skills is missing or empty - skipping skills. Re-run with --refresh-tooling once they exist." >&2
fi

# ---------- 3. hooks (tooling: overwrite allowed) ----------
hooks_source="$template_dir/hooks"
if [ -d "$hooks_source" ] && [ -n "$(ls -A "$hooks_source" 2>/dev/null)" ]; then
    note=""
    [ -d "$hooks_target" ] && note=" (existing files overwritten)"
    mkdir -p "$hooks_target"
    cp -R "$hooks_source/." "$hooks_target/"
    chmod +x "$hooks_target/engram-brief.sh" "$hooks_target/engram-statusline.sh" 2>/dev/null || true
    echo "  - hooks: copied to .claude/hooks/$note"
else
    echo "WARNING: template/hooks is missing or empty - skipping hooks." >&2
fi

# ---------- 4. merge hooks into settings.json (bash-shell hook variant) ----------
# Single-quoted so ${CLAUDE_PROJECT_DIR} stays literal (Claude Code substitutes it).
sessionstart_entry_json='{
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-brief.sh\"",
      "shell": "bash",
      "timeout": 30
    }
  ]
}'
precompact_entry_json='{
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"",
      "shell": "bash",
      "timeout": 180
    }
  ]
}'
sessionend_entry_json='{
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"",
      "shell": "bash",
      "timeout": 300,
      "async": true
    }
  ]
}'

print_manual_merge() {
    cat <<'EOF'
MANUAL STEP REQUIRED: jq is not installed, so the existing .claude/settings.json
was NOT modified (editing JSON without a parser risks corrupting it).
Add this entry to the "SessionStart" array under "hooks" yourself:

{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-brief.sh\"",
            "shell": "bash",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF
}

print_manual_capture() {
    cat <<'EOF'
MANUAL STEP (auto-capture): jq is not installed, so add these two entries under
"hooks" in .claude/settings.json yourself (draft journal entries from the
transcript via headless Claude):

  "PreCompact": [
    { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"", "shell": "bash", "timeout": 180 } ] }
  ],
  "SessionEnd": [
    { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"", "shell": "bash", "timeout": 300, "async": true } ] }
  ]
EOF
}

# Graft one hook-group entry into .hooks.<evt>, idempotent via a command marker
# and safe against a malformed (non-array) existing value. Writes via a temp file.
# Usage: jq_graft <settings_path> <event> <entry_json> <marker>
jq_graft() {
    local sp="$1" evt="$2" entry="$3" marker="$4" tmp
    tmp=$(mktemp) || return 1
    if jq --arg evt "$evt" --arg marker "$marker" --argjson entry "$entry" '
        .hooks = (.hooks // {})
        | .hooks[$evt] = (
            if ((.hooks[$evt] // []) | tostring | contains($marker))
            then (.hooks[$evt] // [])
            else ((.hooks[$evt] // []) + [$entry])
            end)
    ' "$sp" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$sp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

if [ -f "$settings_path" ]; then
    # Existing settings.json.
    if command -v jq >/dev/null 2>&1; then
        merge_ok=1
        jq_graft "$settings_path" "SessionStart" "$sessionstart_entry_json" "engram-brief" || merge_ok=0
        if [ "$autocapture" = 1 ]; then
            jq_graft "$settings_path" "PreCompact" "$precompact_entry_json" "engram-capture" || merge_ok=0
            jq_graft "$settings_path" "SessionEnd" "$sessionend_entry_json" "engram-capture" || merge_ok=0
        fi
        if [ "$merge_ok" = 1 ]; then
            if [ "$autocapture" = 1 ]; then
                echo "  - settings: merged Engram SessionStart + auto-capture (PreCompact + SessionEnd) hooks into settings.json."
            else
                echo "  - settings: merged Engram SessionStart hook into settings.json."
            fi
        else
            echo "WARNING: jq failed to merge one or more hooks into settings.json (malformed shape?) - see manual steps below." >&2
            print_manual_merge
            [ "$autocapture" = 1 ] && print_manual_capture
        fi
    else
        # No jq: never touch an existing settings.json - print manual steps instead.
        if grep -q 'engram-brief' "$settings_path" 2>/dev/null; then
            echo "  - settings: Engram SessionStart hook already registered - settings.json unchanged."
        else
            print_manual_merge
        fi
        if [ "$autocapture" = 1 ]; then
            if grep -q 'engram-capture' "$settings_path" 2>/dev/null; then
                echo "  - settings: Engram auto-capture hooks already registered - settings.json unchanged."
            else
                print_manual_capture
            fi
        fi
    fi
else
    # Fresh settings.json: safe to write directly (no existing content to lose).
    if [ "$autocapture" = 1 ]; then
        cat > "$settings_path" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-brief.sh\"", "shell": "bash", "timeout": 30 } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"", "shell": "bash", "timeout": 180 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-capture.sh\"", "shell": "bash", "timeout": 300, "async": true } ] }
    ]
  }
}
EOF
        echo "  - settings: wrote fresh .claude/settings.json with SessionStart + auto-capture hooks."
    else
        cat > "$settings_path" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-brief.sh\"",
            "shell": "bash",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
EOF
        echo "  - settings: wrote fresh .claude/settings.json with the Engram SessionStart hook."
    fi
fi

if [ "$autocapture" != 1 ]; then
    echo "Auto-capture available: re-run with --auto-capture to enable transcript-draft journaling (PreCompact + SessionEnd)."
fi

# ---------- 5. CLAUDE.md ----------
claude_md="$target/CLAUDE.md"
snippet="$template_dir/CLAUDE-snippet.md"
if [ -f "$claude_md" ] && grep -q 'BEGIN ENGRAM' "$claude_md" 2>/dev/null; then
    echo "  - CLAUDE.md: Engram block already present - unchanged."
else
    if [ -f "$claude_md" ] && [ -s "$claude_md" ] && [ -n "$(tail -c 1 "$claude_md" 2>/dev/null)" ]; then
        printf '\n' >> "$claude_md"    # ensure trailing newline before appending
    fi
    cat "$snippet" >> "$claude_md"
    echo "  - CLAUDE.md: appended Engram block."
fi

# ---------- 6. journal union-merge (prevents same-day merge conflicts in teams) ----------
ga_path="$target/.gitattributes"
if ! grep -q '\.claude/memory/journal/' "$ga_path" 2>/dev/null; then
    if [ -f "$ga_path" ] && [ -s "$ga_path" ] && [ -n "$(tail -c 1 "$ga_path" 2>/dev/null)" ]; then
        printf '\n' >> "$ga_path"
    fi
    {
        echo "# Engram: journals are append-only; union-merge prevents same-day conflicts"
        echo ".claude/memory/journal/*.md merge=union"
        echo ".claude/memory/journal/archive/*.md merge=union"
    } >> "$ga_path"
    echo "  - .gitattributes: journal union-merge rules added."
else
    echo "  - .gitattributes: journal merge rules already present - unchanged."
fi

# ---------- 7. status line (user-level, never clobbers) ----------
# The status line is a per-user singleton: a project-level statusLine would
# override every teammate's personal one, so it is registered in the USER's
# ~/.claude/settings.json instead. The script locates the project from the
# JSON payload Claude Code pipes to it, so this ONE registration covers every
# Engram-fied repo on the machine and renders blank everywhere else.
user_claude="$HOME/.claude"
user_settings="$user_claude/settings.json"
sl_command="bash ~/.claude/engram-statusline.sh"
sl_manual="\"statusLine\": { \"type\": \"command\", \"command\": \"$sl_command\" }"
if [ -f "$hooks_source/engram-statusline.sh" ]; then
    mkdir -p "$user_claude"
    cp "$hooks_source/engram-statusline.sh" "$user_claude/engram-statusline.sh" 2>/dev/null \
        && chmod +x "$user_claude/engram-statusline.sh" 2>/dev/null
    cp "$hooks_source/engram-statusline.ps1" "$user_claude/engram-statusline.ps1" 2>/dev/null
    if [ -f "$user_settings" ] && grep -q 'engram-statusline' "$user_settings" 2>/dev/null; then
        echo "  - status line: already registered in ~/.claude/settings.json (script refreshed)."
    elif [ -f "$user_settings" ] && grep -q '"statusLine"' "$user_settings" 2>/dev/null; then
        echo "  - status line: ~/.claude/settings.json already defines a statusLine - left untouched."
        echo "    To switch to Engram's, set:  $sl_manual"
    elif [ ! -f "$user_settings" ]; then
        cat > "$user_settings" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$sl_command"
  }
}
EOF
        echo "  - status line: wrote fresh ~/.claude/settings.json with the Engram status line."
    elif command -v jq >/dev/null 2>&1; then
        tmp=$(mktemp)
        if jq --arg cmd "$sl_command" \
            '.statusLine = { "type": "command", "command": $cmd }' \
            "$user_settings" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$user_settings"
            echo "  - status line: registered in ~/.claude/settings.json."
        else
            rm -f "$tmp"
            echo "WARNING: jq failed to parse ~/.claude/settings.json - NOT modifying it." >&2
            echo "  To show the Engram status line, add manually:  $sl_manual"
        fi
    else
        echo "MANUAL STEP (optional): jq is not installed, so ~/.claude/settings.json was NOT"
        echo "modified. To show the Engram status line, add:  $sl_manual"
    fi
fi

# ---------- 8. modules ----------
apply_modules

# ---------- summary ----------
echo ""
echo "Engram installed into $target"
echo "Next steps:"
echo "  1. Open Claude Code in the target and run /mem-init to bootstrap memory from the codebase."
echo "  2. New sessions will start with an Engram brief (SessionStart hook)."
echo "  3. The status line at the bottom of Claude Code shows tasks / atlas freshness / journal age."
if [ "$refresh" = "1" ]; then
    echo "  4. Tooling refreshed on an existing install: run /mem-sync in the target - it walks any pending memory-format migrations (see .claude/skills/mem-sync/MIGRATIONS.md)."
fi
exit 0
