#!/usr/bin/env bash
# install.sh -- Install the Engram memory engine into a target project (bash twin of install.ps1).
#
# Usage:
#   ./install.sh --target /path/to/project [--refresh-tooling]
#   ./install.sh /path/to/project
#
# Settings merge strategy: uses jq when available. Without jq, an EXISTING
# settings.json is never touched (manual-merge instructions are printed
# instead of risking corruption); a missing settings.json is written directly.

set -u

# ---------- args ----------
target=""
refresh=0
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--target|-Target)
            [ $# -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 1; }
            target="$2"; shift 2 ;;
        --refresh-tooling|-RefreshTooling)
            refresh=1; shift ;;
        -h|--help)
            echo "Usage: install.sh --target <path> [--refresh-tooling]"; exit 0 ;;
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

# ---------- never clobber memory ----------
memory_present=0
[ -f "$mem_target/MEMORY.md" ] && memory_present=1
if [ "$memory_present" = 1 ] && [ "$refresh" != 1 ]; then
    echo "Engram already installed (memory present) - refusing to touch .claude/memory. Use --refresh-tooling to update skills/hooks only."
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
    chmod +x "$hooks_target/engram-brief.sh" 2>/dev/null || true
    echo "  - hooks: copied to .claude/hooks/$note"
else
    echo "WARNING: template/hooks is missing or empty - skipping hooks." >&2
fi

# ---------- 4. merge hooks into settings.json (bash-shell hook variant) ----------
# Single-quoted so ${CLAUDE_PROJECT_DIR} stays literal (Claude Code substitutes it).
entry_json='{
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/hooks/engram-brief.sh\"",
      "shell": "bash",
      "timeout": 30
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

if [ -f "$settings_path" ] && grep -q 'engram-brief' "$settings_path" 2>/dev/null; then
    echo "  - settings: Engram hook already registered - settings.json unchanged."
elif [ ! -f "$settings_path" ]; then
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
elif command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    if jq --argjson entry "$entry_json" \
        '.hooks = (.hooks // {}) | .hooks.SessionStart = ((.hooks.SessionStart // []) + [$entry])' \
        "$settings_path" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$settings_path"
        echo "  - settings: appended Engram SessionStart hook to existing settings.json."
    else
        rm -f "$tmp"
        echo "WARNING: jq failed to parse existing settings.json - NOT modifying it." >&2
        print_manual_merge
    fi
else
    print_manual_merge
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

# ---------- summary ----------
echo ""
echo "Engram installed into $target"
echo "Next steps:"
echo "  1. Open Claude Code in the target and run /mem-init to bootstrap memory from the codebase."
echo "  2. New sessions will start with an Engram brief (SessionStart hook)."
exit 0
