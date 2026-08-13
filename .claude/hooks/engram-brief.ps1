# engram-brief.ps1 -- Engram SessionStart hook (Windows PowerShell 5.1 compatible).
#
# Reads the SessionStart JSON payload from stdin, emits a short memory brief to
# stdout (Claude Code injects plain stdout directly into the session as context).
#
# Failure philosophy: this runs at every session start, so any failure mode
# (bad JSON, no git, unreadable file, malformed frontmatter) degrades to
# silently skipping that section. The script always exits 0.
#
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM.

$ErrorActionPreference = 'SilentlyContinue'

try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

    # ---------- read stdin JSON ----------
    $sourceVal = ''
    $cwdVal = ''
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw -and $raw.Trim().Length -gt 0) {
            $payload = $raw | ConvertFrom-Json
            if ($payload -and $payload.PSObject.Properties['source']) { $sourceVal = [string]$payload.source }
            if ($payload -and $payload.PSObject.Properties['cwd'])    { $cwdVal    = [string]$payload.cwd }
        }
    } catch { }

    # ---------- resolve project root ----------
    $root = $env:CLAUDE_PROJECT_DIR
    if (-not $root) { $root = $cwdVal }
    if (-not $root) { $root = (Get-Location).Path }

    # ---------- locate the Engram memory (root itself, then pin file, then one
    # level down) ----------
    # Nested: Claude launched in a PARENT of the Engram-fied repo -> a pin file
    # (.claude\engram-root, written by the installer) or a one-level-down probe
    # (statusline's algorithm) resolves the child; $subLabel tags the brief
    # header so it's clear which project this is. An invalid/dangling pin falls
    # through to the probe rather than failing hard.
    $subLabel = ''
    if (-not (Test-Path -LiteralPath (Join-Path $root '.claude\memory\MEMORY.md'))) {
        $pinLine = ''
        $pinFile = Join-Path $root '.claude\engram-root'
        if (Test-Path -LiteralPath $pinFile -PathType Leaf) {
            try {
                foreach ($pl in [System.IO.File]::ReadAllLines($pinFile)) {
                    $t = $pl.Trim()
                    if ($t) { $pinLine = $t; break }
                }
            } catch { }
        }
        $pinTarget = $null
        if ($pinLine) {
            $candidate = Join-Path $root $pinLine
            if (Test-Path -LiteralPath (Join-Path $candidate '.claude\memory\MEMORY.md')) {
                $pinTarget = $candidate
            }
        }
        if ($pinTarget) {
            $root = $pinTarget
            $subLabel = Split-Path -Leaf $root
        } else {
            $nested = @()
            try {
                $nested = @(Get-ChildItem -LiteralPath $root -Directory |
                    Sort-Object Name |
                    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.claude\memory\MEMORY.md') })
            } catch { }
            if ($nested.Count -gt 0) {
                $root = $nested[0].FullName
                $subLabel = $nested[0].Name
            }
        }
    }

    $memDir   = Join-Path $root '.claude\memory'
    $memoryMd = Join-Path $memDir 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $memoryMd)) { exit 0 }   # no Engram here -> silent

    $out = New-Object System.Collections.Generic.List[string]

    # ---------- compact: reminder only ----------
    if ($sourceVal -eq 'compact') {
        $out.Add('## Engram: post-compaction check')
        $out.Add('Context was just compacted. Anything learned before compaction and not yet journaled is at risk of being lost. If there are unlogged milestones, dead ends, or decisions from earlier in this session, append a journal entry now (follow /mem-journal), then continue.')
        # Re-inject the tail of today's journal: if a PreCompact capture hook just wrote
        # a draft, this is what carries it into the post-compaction context.
        try {
            $todayJ = Join-Path $memDir ('journal\' + (Get-Date -Format 'yyyy-MM-dd') + '.md')
            if (Test-Path -LiteralPath $todayJ) {
                $jl = [System.IO.File]::ReadAllLines($todayJ)
                $tail = @($jl | Select-Object -Last 25)
                if ($tail.Count -gt 0) {
                    $out.Add('')
                    $out.Add('### Today''s journal (tail)')
                    foreach ($tl in $tail) { $out.Add($tl) }
                }
            }
        } catch { }
        foreach ($line in $out) { Write-Output $line }
        exit 0
    }

    # ---------- session brief (startup / resume / clear / anything else) ----------
    $briefHeader = '## Engram session brief'
    if ($subLabel) { $briefHeader = $briefHeader + ' (' + $subLabel + ')' }
    $out.Add($briefHeader)
    $out.Add('Details live in .claude/memory/ (MEMORY.md is the index).')
    $out.Add('')

    $memoryText = ''
    try { $memoryText = [System.IO.File]::ReadAllText($memoryMd) } catch { }
    $memoryEmpty = ($memoryText.IndexOf('STATUS: EMPTY') -ge 0)

    # ----- Tasks: ## Now and ## Next sections from tasks.md (cap 15 lines) -----
    try {
        $tasksPath = Join-Path $memDir 'tasks.md'
        if (Test-Path -LiteralPath $tasksPath) {
            $tLines = [System.IO.File]::ReadAllLines($tasksPath)
            $taskLines = New-Object System.Collections.Generic.List[string]
            $inWanted = $false
            $itemCount = 0
            foreach ($l in $tLines) {
                if ($l -match '^##\s+(.+?)\s*$') {
                    $sect = $matches[1]
                    $inWanted = ($sect -eq 'Now' -or $sect -eq 'Next')
                    if ($inWanted -and $taskLines.Count -lt 15) { $taskLines.Add($l) }
                    continue
                }
                if ($inWanted -and $l.Trim().Length -gt 0 -and $taskLines.Count -lt 15) {
                    $taskLines.Add($l)
                    $itemCount++
                }
            }
            $out.Add('### Tasks')
            if ($itemCount -gt 0) {
                foreach ($l in $taskLines) { $out.Add($l) }
            } else {
                $out.Add('No active tasks in tasks.md.')
            }
            $out.Add('')
        }
    } catch { }

    if ($memoryEmpty) {
        $out.Add('Memory is empty - run /mem-init to bootstrap it from the codebase.')
    } else {

        # ----- Recent journal: 2 most recent daily files, last 2 entries each (~40 lines) -----
        try {
            $out.Add('### Recent journal')
            $journalDir = Join-Path $memDir 'journal'
            $jFiles = @()
            if (Test-Path -LiteralPath $journalDir) {
                # Non-recursive listing naturally excludes journal\archive\.
                $jFiles = @(Get-ChildItem -LiteralPath $journalDir -File -Filter '*.md' |
                    Where-Object { $_.Name -notlike '_*' } |
                    Sort-Object Name -Descending |
                    Select-Object -First 2)
            }
            if ($jFiles.Count -eq 0) {
                $out.Add('No journal entries yet.')
            } else {
                $budget = 40
                foreach ($jf in $jFiles) {
                    if ($budget -le 0) { break }
                    $jLines = @()
                    try { $jLines = [System.IO.File]::ReadAllLines($jf.FullName) } catch { continue }
                    # Date header: first '# ...' line, else derive from filename.
                    $header = $null
                    foreach ($l in $jLines) { if ($l -match '^#\s') { $header = $l; break } }
                    if (-not $header) { $header = '# ' + $jf.BaseName }
                    $out.Add($header); $budget--
                    # Entries start at lines beginning '## '; keep the last 2.
                    $starts = @()
                    for ($i = 0; $i -lt $jLines.Count; $i++) {
                        if ($jLines[$i] -like '## *') { $starts += $i }
                    }
                    if ($starts.Count -gt 0) {
                        $from = $starts[[Math]::Max(0, $starts.Count - 2)]
                        for ($i = $from; ($i -lt $jLines.Count) -and ($budget -gt 0); $i++) {
                            if ($jLines[$i].Trim().Length -gt 0) { $out.Add($jLines[$i]); $budget-- }
                        }
                    }
                }
            }
            $out.Add('')
        } catch { }

        # ----- Atlas freshness: footprint-manifest set-compare (engram-manifest twin) -----
        # One script call replaces the old per-card `git log` loop. States:
        # VERIFIED = trust the card; DRIFTED = trust minus the listed delta files;
        # ASSUMED = never verified (map, not truth); DIRTY = uncommitted edits
        # touch card footprints (designed state -- manifests see commits only).
        try {
            $isGit = $false
            $gitOut = git -C $root rev-parse --is-inside-work-tree 2>$null
            if ($LASTEXITCODE -eq 0 -and "$gitOut" -match 'true') { $isGit = $true }

            if ($isGit) {
                $atlasDir = Join-Path $memDir 'atlas'
                $mScript = Join-Path $root '.claude/scripts/engram-manifest.ps1'
                if (Test-Path -LiteralPath $mScript) {
                    $mStatus = @(& $mScript status --root $root 2>$null)
                    if ($mStatus.Count -gt 0) {
                        $nTotal = 0; $nVerified = 0
                        $driftList = New-Object System.Collections.Generic.List[string]
                        $assumedList = New-Object System.Collections.Generic.List[string]
                        $dirtyDetail = ''
                        foreach ($ml in $mStatus) {
                            if (-not $ml) { continue }
                            $f = ([string]$ml) -split "`t", 3
                            if ($f.Count -lt 3) { continue }
                            switch ($f[0]) {
                                'VERIFIED'   { $nTotal++; $nVerified++ }
                                'DRIFTED'    { $nTotal++; $driftList.Add($f[1] + ' (' + $f[2] + ')') }
                                'NOMANIFEST' { $nTotal++; $driftList.Add($f[1] + ' (' + $f[2] + ')') }
                                'ASSUMED'    { $nTotal++; $assumedList.Add($f[1]) }
                                'DIRTY'      { $dirtyDetail = $f[2] }
                            }
                        }
                        if ($nTotal -gt 0) {
                            $out.Add('### Atlas freshness')
                            if ($driftList.Count -eq 0 -and $assumedList.Count -eq 0) {
                                $out.Add("All $nTotal atlas cards VERIFIED.")
                            } else {
                                if ($driftList.Count -gt 0) {
                                    $out.Add('DRIFTED - consider /mem-sync: ' + ($driftList -join ', '))
                                }
                                if ($assumedList.Count -gt 0) {
                                    $out.Add('ASSUMED (never verified; map, not truth): ' + ($assumedList -join ', '))
                                }
                            }
                            if ($dirtyDetail) {
                                $out.Add('Uncommitted (manifests see commits only): ' + $dirtyDetail)
                            }
                        }
                    }
                } else {
                    $out.Add('### Atlas freshness')
                    $out.Add('Unavailable - engram-manifest script missing; refresh Engram tooling (installer -RefreshTooling).')
                }

                # ----- Recent activity: commits in the last 24h touching each card's paths -----
                # Omit the section entirely when nothing changed (silence beats noise).
                $cards = @()
                if (Test-Path -LiteralPath $atlasDir) {
                    $cards = @(Get-ChildItem -LiteralPath $atlasDir -File -Filter '*.md' |
                        Where-Object { $_.Name -notlike '_*' } |
                        Sort-Object Name)
                }
                if ($cards.Count -gt 0) {
                    try {
                        $recentReports = New-Object System.Collections.Generic.List[string]
                        foreach ($card in $cards) {
                            try {
                                $cLines = [System.IO.File]::ReadAllLines($card.FullName)
                                if ($cLines.Count -lt 2 -or $cLines[0].Trim() -ne '---') { continue }
                                $module = ''; $cardPaths = @(); $inPaths = $false
                                for ($i = 1; $i -lt $cLines.Count; $i++) {
                                    $l = $cLines[$i]
                                    if ($l.Trim() -eq '---') { break }
                                    if ($inPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                                        $cardPaths += $matches[1].Trim('"').Trim("'")
                                        continue
                                    }
                                    $inPaths = $false
                                    if ($l -match '^module:\s*(.+?)\s*$')  { $module = $matches[1]; continue }
                                    if ($l -match '^paths:\s*$')           { $inPaths = $true; continue }
                                }
                                if (-not $module) { $module = $card.BaseName }
                                if ($cardPaths.Count -eq 0) { continue }   # malformed card: skip silently
                                $rlog = @(git -C $root log --oneline --since=24.hours -- $cardPaths 2>$null)
                                if ($LASTEXITCODE -ne 0) { continue }
                                $rn = @($rlog | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
                                if ($rn -gt 0) {
                                    $rplural = 's'
                                    if ($rn -eq 1) { $rplural = '' }
                                    $recentReports.Add("$module ($rn commit$rplural)")
                                }
                            } catch { }
                        }
                        if ($recentReports.Count -gt 0) {
                            $out.Add('### Recent activity (24h)')
                            $out.Add($recentReports -join ', ')
                        }
                    } catch { }
                }
            }
        } catch { }

        # ----- Architecture overview: same frontmatter contract as a card -----
        try {
            if ($isGit) {
                $archPath = Join-Path $memDir 'architecture.md'
                if (Test-Path -LiteralPath $archPath) {
                    $aLines = [System.IO.File]::ReadAllLines($archPath)
                    if ($aLines.Count -ge 2 -and $aLines[0].Trim() -eq '---') {
                        $aVerified = ''; $aPaths = @(); $inAPaths = $false
                        for ($i = 1; $i -lt $aLines.Count; $i++) {
                            $l = $aLines[$i]
                            if ($l.Trim() -eq '---') { break }
                            if ($inAPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                                $aPaths += $matches[1].Trim('"').Trim("'")
                                continue
                            }
                            $inAPaths = $false
                            if ($l -match '^verified:\s*(\S+)') { $aVerified = $matches[1]; continue }
                            if ($l -match '^paths:\s*$')        { $inAPaths = $true; continue }
                        }
                        if ($aPaths.Count -gt 0) {
                            $archMsg = ''
                            if ((-not $aVerified) -or ($aVerified -match '^0+$')) {
                                $archMsg = 'Architecture overview: no baseline - run /mem-arch update.'
                            } else {
                                $objType = (git -C $root cat-file -t $aVerified 2>$null)
                                if ($LASTEXITCODE -ne 0 -or "$objType".Trim() -ne 'commit') {
                                    $archMsg = 'Architecture overview: unknown baseline - run /mem-arch update.'
                                } else {
                                    $logLines = @(git -C $root log --oneline "$aVerified..HEAD" -- $aPaths 2>$null)
                                    if ($LASTEXITCODE -eq 0) {
                                        $behind = @($logLines | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
                                        if ($behind -gt 0) {
                                            $plural = 's'
                                            if ($behind -eq 1) { $plural = '' }
                                            $archMsg = "Architecture overview: $behind commit$plural behind - run /mem-arch update."
                                        }
                                    }
                                }
                            }
                            if ($archMsg) { $out.Add($archMsg) }
                        }
                    }
                }
            }
        } catch { }
    }

    # ---------- emit, hard-capped at 80 lines ----------
    $emitted = 0
    foreach ($line in $out) {
        if ($emitted -ge 80) { break }
        Write-Output $line
        $emitted++
    }
    exit 0
} catch {
    exit 0
}
