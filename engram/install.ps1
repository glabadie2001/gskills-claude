# install.ps1 -- Install the Engram memory engine into a target project.
#
# Usage:
#   powershell -NoProfile -File install.ps1 -Target C:\path\to\project [-RefreshTooling]
#
# Windows PowerShell 5.1 compatible (no ??, no ternary, no -AsHashtable).
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [switch]$RefreshTooling,

    [switch]$AutoCapture
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Step($msg) { Write-Host "  - $msg" }

# ---------- resolve paths ----------
$engineRoot  = $PSScriptRoot
$templateDir = Join-Path $engineRoot 'template'
if (-not (Test-Path -LiteralPath $templateDir -PathType Container)) {
    Write-Host "ERROR: template directory not found at $templateDir" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Host "ERROR: target directory does not exist: $Target" -ForegroundColor Red
    exit 1
}
$Target = (Resolve-Path -LiteralPath $Target).Path

Write-Host "Engram installer"
Write-Host "  engine: $engineRoot"
Write-Host "  target: $Target"
Write-Host ""

# ---------- git check (warn only) ----------
if (-not (Test-Path (Join-Path $Target '.git'))) {
    Write-Warning "Target is not a git repo: staleness tracking will be disabled until git init."
}

$claudeDir    = Join-Path $Target '.claude'
$memTarget    = Join-Path $claudeDir 'memory'
$skillsTarget = Join-Path $claudeDir 'skills'
$hooksTarget  = Join-Path $claudeDir 'hooks'
$settingsPath = Join-Path $claudeDir 'settings.json'

# ---------- never clobber memory ----------
$memoryPresent = Test-Path -LiteralPath (Join-Path $memTarget 'MEMORY.md')
if ($memoryPresent -and -not $RefreshTooling) {
    Write-Host "Engram already installed (memory present) - refusing to touch .claude/memory. Use -RefreshTooling to refresh skills/hooks/settings/CLAUDE.md (memory is never touched)."
    exit 0
}

if (-not (Test-Path -LiteralPath $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# ---------- 1. memory ----------
if ($memoryPresent) {
    Write-Step "memory: present - left untouched (RefreshTooling mode)."
} else {
    New-Item -ItemType Directory -Path $memTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $templateDir 'memory\*') -Destination $memTarget -Recurse -Force
    # Ensure expected directories exist even if the template lacks them,
    # and drop a .gitkeep in any that end up empty.
    foreach ($sub in @('atlas', 'journal', 'journal\archive', 'decisions')) {
        $p = Join-Path $memTarget $sub
        if (-not (Test-Path -LiteralPath $p)) {
            New-Item -ItemType Directory -Path $p -Force | Out-Null
        }
        $hasChild = Get-ChildItem -LiteralPath $p -Force | Select-Object -First 1
        if (-not $hasChild) {
            [System.IO.File]::WriteAllText((Join-Path $p '.gitkeep'), '', $utf8NoBom)
        }
    }
    Write-Step "memory: copied template to .claude\memory\"
}

# ---------- 2. skills (tooling: overwrite allowed) ----------
$skillsSource = Join-Path $templateDir 'skills'
$haveSkills = $false
if (Test-Path -LiteralPath $skillsSource -PathType Container) {
    $haveSkills = [bool](Get-ChildItem -LiteralPath $skillsSource -Force | Select-Object -First 1)
}
if ($haveSkills) {
    $overwriting = Test-Path -LiteralPath $skillsTarget
    New-Item -ItemType Directory -Path $skillsTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $skillsSource '*') -Destination $skillsTarget -Recurse -Force
    if ($overwriting) {
        Write-Step "skills: copied to .claude\skills\ (existing files overwritten)."
    } else {
        Write-Step "skills: copied to .claude\skills\"
    }
} else {
    Write-Warning "template\skills is missing or empty - skipping skills. Re-run with -RefreshTooling once they exist."
}

# ---------- 3. hooks (tooling: overwrite allowed) ----------
$hooksSource = Join-Path $templateDir 'hooks'
if ((Test-Path -LiteralPath $hooksSource -PathType Container) -and
    (Get-ChildItem -LiteralPath $hooksSource -Force | Select-Object -First 1)) {
    $overwriting = Test-Path -LiteralPath $hooksTarget
    New-Item -ItemType Directory -Path $hooksTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $hooksSource '*') -Destination $hooksTarget -Recurse -Force
    if ($overwriting) {
        Write-Step "hooks: copied to .claude\hooks\ (existing files overwritten)."
    } else {
        Write-Step "hooks: copied to .claude\hooks\"
    }
} else {
    Write-Warning "template\hooks is missing or empty - skipping hooks."
}

# ---------- 4. merge hooks into settings.json ----------
$fragPath = Join-Path $templateDir 'settings-fragment.json'

# Graft a single hook-group entry into settings.hooks.<evt>, guarding the
# well-formedness (array of objects) and staying idempotent via a command marker.
# Returns 'added', 'present', or 'invalid'.
function Add-EngramHookEntry($settingsObj, $evtName, $entry, $marker) {
    if (-not $settingsObj.PSObject.Properties['hooks'] -or $null -eq $settingsObj.hooks) {
        $settingsObj | Add-Member -MemberType NoteProperty -Name 'hooks' -Value (New-Object PSObject) -Force
    }
    if (-not $settingsObj.hooks.PSObject.Properties[$evtName] -or $null -eq $settingsObj.hooks.$evtName) {
        $settingsObj.hooks | Add-Member -MemberType NoteProperty -Name $evtName -Value @() -Force
    }
    $existingArr = @($settingsObj.hooks.$evtName) | Where-Object { $null -ne $_ }
    $existingJson = ''
    try { $existingJson = [string]($settingsObj.hooks.$evtName | ConvertTo-Json -Depth 50) } catch { }
    if ($existingJson -and $existingJson.IndexOf($marker) -ge 0) { return 'present' }
    # Guard: a string or other non-object shape is an unsupported/legacy config we must not corrupt.
    $invalid = $false
    foreach ($e in $existingArr) {
        if ($e -isnot [System.Management.Automation.PSCustomObject]) { $invalid = $true }
    }
    if ($invalid) { return 'invalid' }
    $settingsObj.hooks.$evtName = @($existingArr) + @(, $entry)
    return 'added'
}

try {
    $frag = Get-Content -LiteralPath $fragPath -Raw | ConvertFrom-Json
    $engramEntry = $frag.hooks.SessionStart[0]
    $preCompactEntry = $null
    $sessionEndEntry = $null
    if ($frag.PSObject.Properties['_autocapture_hooks'] -and $frag._autocapture_hooks) {
        if ($frag._autocapture_hooks.PSObject.Properties['PreCompact']) { $preCompactEntry = $frag._autocapture_hooks.PreCompact[0] }
        if ($frag._autocapture_hooks.PSObject.Properties['SessionEnd']) { $sessionEndEntry = $frag._autocapture_hooks.SessionEnd[0] }
    }

    if (-not (Test-Path -LiteralPath $settingsPath)) {
        # Fresh settings.json: just the hooks block (no _comment).
        $settings = New-Object PSObject
        [void](Add-EngramHookEntry $settings 'SessionStart' $engramEntry 'engram-brief')
        if ($AutoCapture) {
            if ($preCompactEntry) { [void](Add-EngramHookEntry $settings 'PreCompact' $preCompactEntry 'engram-capture') }
            if ($sessionEndEntry) { [void](Add-EngramHookEntry $settings 'SessionEnd' $sessionEndEntry 'engram-capture') }
        }
        $json = $settings | ConvertTo-Json -Depth 50
        [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
        if ($AutoCapture) {
            Write-Step "settings: wrote fresh .claude\settings.json with Engram SessionStart + auto-capture (PreCompact + SessionEnd) hooks."
        } else {
            Write-Step "settings: wrote fresh .claude\settings.json with the Engram SessionStart hook."
        }
    } else {
        $rawSettings = Get-Content -LiteralPath $settingsPath -Raw
        $settings = $null
        try { $settings = $rawSettings | ConvertFrom-Json } catch { $settings = $null }
        if ($null -eq $settings) {
            Write-Warning "Could not parse existing .claude\settings.json - NOT modifying it. Merge this into hooks manually:"
            Write-Host ((Get-Content -LiteralPath $fragPath -Raw))
        } else {
            $changed = $false

            $r1 = Add-EngramHookEntry $settings 'SessionStart' $engramEntry 'engram-brief'
            if ($r1 -eq 'added') {
                $changed = $true
                Write-Step "settings: appended Engram SessionStart hook to existing settings.json."
            } elseif ($r1 -eq 'present') {
                Write-Step "settings: Engram SessionStart hook already registered - unchanged."
            } elseif ($r1 -eq 'invalid') {
                Write-Warning "existing hooks.SessionStart has an unsupported shape (non-object entries) - NOT modifying it. Add this entry to the SessionStart array manually:"
                Write-Host ((Get-Content -LiteralPath $fragPath -Raw))
            }

            if ($AutoCapture) {
                foreach ($pair in @(@('PreCompact', $preCompactEntry), @('SessionEnd', $sessionEndEntry))) {
                    $evt = $pair[0]; $ent = $pair[1]
                    if (-not $ent) { continue }
                    $rc = Add-EngramHookEntry $settings $evt $ent 'engram-capture'
                    if ($rc -eq 'added') {
                        $changed = $true
                        Write-Step "settings: appended Engram auto-capture $evt hook to existing settings.json."
                    } elseif ($rc -eq 'present') {
                        Write-Step "settings: Engram auto-capture $evt hook already registered - unchanged."
                    } elseif ($rc -eq 'invalid') {
                        Write-Warning "existing hooks.$evt has an unsupported shape - NOT modifying it. Add the $evt entry from template\settings-fragment.json (_autocapture_hooks) manually."
                    }
                }
            }

            if ($changed) {
                $json = $settings | ConvertTo-Json -Depth 50
                [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
            }
        }
    }
} catch {
    Write-Warning ("settings merge failed: " + $_.Exception.Message)
    Write-Warning "Merge template\settings-fragment.json into <target>\.claude\settings.json manually."
}

if (-not $AutoCapture) {
    Write-Host "Auto-capture available: re-run with -AutoCapture to enable transcript-draft journaling (PreCompact + SessionEnd)."
}

# ---------- 5. CLAUDE.md ----------
try {
    $claudeMdPath = Join-Path $Target 'CLAUDE.md'
    $snippet = [System.IO.File]::ReadAllText((Join-Path $templateDir 'CLAUDE-snippet.md'))
    $existing = ''
    if (Test-Path -LiteralPath $claudeMdPath) {
        $existing = [System.IO.File]::ReadAllText($claudeMdPath)
    }
    if ($existing.IndexOf('BEGIN ENGRAM') -ge 0) {
        Write-Step "CLAUDE.md: Engram block already present - unchanged."
    } else {
        $sep = ''
        if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
            # Match the file's existing line-ending style.
            if ($existing.IndexOf("`r`n") -ge 0) { $sep = "`r`n" } else { $sep = "`n" }
        }
        [System.IO.File]::WriteAllText($claudeMdPath, $existing + $sep + $snippet, $utf8NoBom)
        Write-Step "CLAUDE.md: appended Engram block."
    }
} catch {
    Write-Warning ("CLAUDE.md update failed: " + $_.Exception.Message)
}

# ---------- 6. journal union-merge (prevents same-day merge conflicts in teams) ----------
try {
    $gaPath = Join-Path $Target '.gitattributes'
    $gaExisting = ''
    if (Test-Path -LiteralPath $gaPath) { $gaExisting = [System.IO.File]::ReadAllText($gaPath) }
    if ($gaExisting.IndexOf('.claude/memory/journal/') -lt 0) {
        $gaBlock = "# Engram: journals are append-only; union-merge prevents same-day conflicts`n" +
                   ".claude/memory/journal/*.md merge=union`n" +
                   ".claude/memory/journal/archive/*.md merge=union`n"
        $gaSep = ''
        if ($gaExisting.Length -gt 0 -and -not $gaExisting.EndsWith("`n")) { $gaSep = "`n" }
        [System.IO.File]::WriteAllText($gaPath, $gaExisting + $gaSep + $gaBlock, $utf8NoBom)
        Write-Step ".gitattributes: journal union-merge rules added."
    } else {
        Write-Step ".gitattributes: journal merge rules already present - unchanged."
    }
} catch {
    Write-Warning (".gitattributes update failed: " + $_.Exception.Message)
}

# ---------- 7. status line (user-level, never clobbers) ----------
# The status line is a per-user singleton: a project-level statusLine would
# override every teammate's personal one, so it is registered in the USER's
# ~\.claude\settings.json instead. The script locates the project from the
# JSON payload Claude Code pipes to it, so this ONE registration covers every
# Engram-fied repo on the machine and renders blank everywhere else.
try {
    $userClaude   = Join-Path $env:USERPROFILE '.claude'
    $userSettings = Join-Path $userClaude 'settings.json'
    $slSource     = Join-Path $hooksSource 'engram-statusline.sh'
    $slCommand    = 'bash ~/.claude/engram-statusline.sh'
    $slManual     = '"statusLine": { "type": "command", "command": "' + $slCommand + '" }'
    if (Test-Path -LiteralPath $slSource) {
        if (-not (Test-Path -LiteralPath $userClaude)) {
            New-Item -ItemType Directory -Path $userClaude -Force | Out-Null
        }
        Copy-Item -LiteralPath $slSource -Destination (Join-Path $userClaude 'engram-statusline.sh') -Force
        $slPs1 = Join-Path $hooksSource 'engram-statusline.ps1'
        if (Test-Path -LiteralPath $slPs1) {
            Copy-Item -LiteralPath $slPs1 -Destination (Join-Path $userClaude 'engram-statusline.ps1') -Force
        }
        if (Test-Path -LiteralPath $userSettings) {
            $rawUser = Get-Content -LiteralPath $userSettings -Raw
            $userObj = $null
            try { $userObj = $rawUser | ConvertFrom-Json } catch { $userObj = $null }
            if ($rawUser.IndexOf('engram-statusline') -ge 0) {
                Write-Step "status line: already registered in ~\.claude\settings.json (script refreshed)."
            } elseif ($null -eq $userObj) {
                Write-Warning "Could not parse ~\.claude\settings.json - NOT modifying it. To show the Engram status line, add manually: $slManual"
            } elseif ($userObj.PSObject.Properties['statusLine'] -and $null -ne $userObj.statusLine) {
                Write-Step "status line: ~\.claude\settings.json already defines a statusLine - left untouched."
                Write-Host "    To switch to Engram's, set:  $slManual"
            } else {
                $slObj = New-Object PSObject
                $slObj | Add-Member -MemberType NoteProperty -Name 'type' -Value 'command'
                $slObj | Add-Member -MemberType NoteProperty -Name 'command' -Value $slCommand
                $userObj | Add-Member -MemberType NoteProperty -Name 'statusLine' -Value $slObj -Force
                $json = $userObj | ConvertTo-Json -Depth 50
                [System.IO.File]::WriteAllText($userSettings, $json, $utf8NoBom)
                Write-Step "status line: registered in ~\.claude\settings.json."
            }
        } else {
            $settingsObj = New-Object PSObject
            $slObj = New-Object PSObject
            $slObj | Add-Member -MemberType NoteProperty -Name 'type' -Value 'command'
            $slObj | Add-Member -MemberType NoteProperty -Name 'command' -Value $slCommand
            $settingsObj | Add-Member -MemberType NoteProperty -Name 'statusLine' -Value $slObj
            $json = $settingsObj | ConvertTo-Json -Depth 50
            [System.IO.File]::WriteAllText($userSettings, $json, $utf8NoBom)
            Write-Step "status line: wrote fresh ~\.claude\settings.json with the Engram status line."
        }
    }
} catch {
    Write-Warning ("status line setup failed: " + $_.Exception.Message)
}

# ---------- summary ----------
Write-Host ""
Write-Host "Engram installed into $Target"
Write-Host "Next steps:"
Write-Host "  1. Open Claude Code in the target and run /mem-init to bootstrap memory from the codebase."
Write-Host "  2. New sessions will start with an Engram brief (SessionStart hook)."
Write-Host "  3. The status line at the bottom of Claude Code shows tasks / atlas freshness / journal age."
if ($RefreshTooling) {
    Write-Host "  4. Tooling refreshed on an existing install: run /mem-sync in the target - it walks any pending memory-format migrations (see .claude\skills\mem-sync\MIGRATIONS.md)."
}
exit 0
