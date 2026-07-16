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

    [switch]$RefreshTooling
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
try {
    $frag = Get-Content -LiteralPath $fragPath -Raw | ConvertFrom-Json
    $engramEntry = $frag.hooks.SessionStart[0]

    if (-not (Test-Path -LiteralPath $settingsPath)) {
        # Fresh settings.json: just the hooks block (no _comment).
        $settings = New-Object PSObject
        $hooksObj = New-Object PSObject
        $hooksObj | Add-Member -MemberType NoteProperty -Name 'SessionStart' -Value @(, $engramEntry)
        $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $hooksObj
        $json = $settings | ConvertTo-Json -Depth 50
        [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
        Write-Step "settings: wrote fresh .claude\settings.json with the Engram SessionStart hook."
    } else {
        $rawSettings = Get-Content -LiteralPath $settingsPath -Raw
        $settings = $null
        try { $settings = $rawSettings | ConvertFrom-Json } catch { $settings = $null }
        if ($null -eq $settings) {
            Write-Warning "Could not parse existing .claude\settings.json - NOT modifying it. Merge this into hooks.SessionStart manually:"
            Write-Host ((Get-Content -LiteralPath $fragPath -Raw))
        } else {
            if (-not $settings.PSObject.Properties['hooks'] -or $null -eq $settings.hooks) {
                $settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value (New-Object PSObject) -Force
            }
            if (-not $settings.hooks.PSObject.Properties['SessionStart'] -or $null -eq $settings.hooks.SessionStart) {
                $settings.hooks | Add-Member -MemberType NoteProperty -Name 'SessionStart' -Value @() -Force
            }
            # Guard: only graft into a well-formed SessionStart (array of objects).
            # A string or other shape means an unsupported/legacy config we must not corrupt.
            $ssExisting = @($settings.hooks.SessionStart) | Where-Object { $null -ne $_ }
            $ssInvalid = $false
            foreach ($e in $ssExisting) {
                if ($e -isnot [System.Management.Automation.PSCustomObject]) { $ssInvalid = $true }
            }
            $existingJson = ''
            try { $existingJson = [string]($settings.hooks.SessionStart | ConvertTo-Json -Depth 50) } catch { }
            if ($existingJson -and $existingJson.IndexOf('engram-brief') -ge 0) {
                Write-Step "settings: Engram hook already registered - settings.json unchanged."
            } elseif ($ssInvalid) {
                Write-Warning "existing hooks.SessionStart has an unsupported shape (non-object entries) - NOT modifying settings.json. Add this entry to the SessionStart array manually:"
                Write-Host ((Get-Content -LiteralPath $fragPath -Raw))
            } else {
                $settings.hooks.SessionStart = @($ssExisting) + @(, $engramEntry)
                $json = $settings | ConvertTo-Json -Depth 50
                [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
                Write-Step "settings: appended Engram SessionStart hook to existing settings.json."
            }
        }
    }
} catch {
    Write-Warning ("settings merge failed: " + $_.Exception.Message)
    Write-Warning "Merge template\settings-fragment.json into <target>\.claude\settings.json manually."
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

# ---------- summary ----------
Write-Host ""
Write-Host "Engram installed into $Target"
Write-Host "Next steps:"
Write-Host "  1. Open Claude Code in the target and run /mem-init to bootstrap memory from the codebase."
Write-Host "  2. New sessions will start with an Engram brief (SessionStart hook)."
exit 0
