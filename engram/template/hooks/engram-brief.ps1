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
    $out.Add('## Engram session brief')
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

        # ----- Staleness: compare atlas card baselines against git history -----
        try {
            $isGit = $false
            $gitOut = git -C $root rev-parse --is-inside-work-tree 2>$null
            if ($LASTEXITCODE -eq 0 -and "$gitOut" -match 'true') { $isGit = $true }

            if ($isGit) {
                $atlasDir = Join-Path $memDir 'atlas'
                $cards = @()
                if (Test-Path -LiteralPath $atlasDir) {
                    $cards = @(Get-ChildItem -LiteralPath $atlasDir -File -Filter '*.md' |
                        Where-Object { $_.Name -notlike '_*' } |
                        Sort-Object Name)
                }
                if ($cards.Count -gt 0) {
                    $staleReports = New-Object System.Collections.Generic.List[string]
                    $recentList = New-Object System.Collections.Generic.List[object]
                    $checked = 0
                    foreach ($card in $cards) {
                        try {
                            $cLines = [System.IO.File]::ReadAllLines($card.FullName)
                            if ($cLines.Count -lt 2 -or $cLines[0].Trim() -ne '---') { continue }
                            $module = ''; $verified = ''; $cardPaths = @(); $inPaths = $false
                            for ($i = 1; $i -lt $cLines.Count; $i++) {
                                $l = $cLines[$i]
                                if ($l.Trim() -eq '---') { break }
                                if ($inPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                                    $cardPaths += $matches[1].Trim('"').Trim("'")
                                    continue
                                }
                                $inPaths = $false
                                if ($l -match '^module:\s*(.+?)\s*$')  { $module = $matches[1]; continue }
                                if ($l -match '^verified:\s*(\S+)')    { $verified = $matches[1]; continue }
                                if ($l -match '^paths:\s*$')           { $inPaths = $true; continue }
                            }
                            if (-not $module) { $module = $card.BaseName }
                            if ($cardPaths.Count -eq 0) { continue }   # malformed card: skip silently
                            $checked++
                            $recentList.Add(@{ m = $module; p = $cardPaths })
                            if ((-not $verified) -or ($verified -match '^0+$')) {
                                $staleReports.Add("$module (unknown baseline)")
                                continue
                            }
                            $objType = (git -C $root cat-file -t $verified 2>$null)
                            if ($LASTEXITCODE -ne 0 -or "$objType".Trim() -ne 'commit') {
                                $staleReports.Add("$module (unknown baseline)")
                                continue
                            }
                            $logLines = @(git -C $root log --oneline "$verified..HEAD" -- $cardPaths 2>$null)
                            if ($LASTEXITCODE -ne 0) {
                                $staleReports.Add("$module (unknown baseline)")
                                continue
                            }
                            $behind = @($logLines | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
                            if ($behind -gt 0) {
                                $plural = 's'
                                if ($behind -eq 1) { $plural = '' }
                                $staleReports.Add("$module ($behind commit$plural behind)")
                            }
                        } catch { }
                    }
                    if ($checked -gt 0) {
                        $out.Add('### Atlas freshness')
                        if ($staleReports.Count -eq 0) {
                            $out.Add("All $checked atlas cards fresh.")
                        } else {
                            $out.Add('STALE cards - consider /mem-sync: ' + ($staleReports -join ', '))
                        }
                    }

                    # ----- Recent activity: commits in the last 24h touching each card's paths -----
                    # Reuses the cards parsed above (module + paths); omit the section entirely
                    # when nothing changed (silence beats noise). Same silent-failure discipline.
                    try {
                        if ($recentList.Count -gt 0) {
                            $recentReports = New-Object System.Collections.Generic.List[string]
                            foreach ($rc in $recentList) {
                                $rlog = @(git -C $root log --oneline --since=24.hours -- $rc.p 2>$null)
                                if ($LASTEXITCODE -ne 0) { continue }
                                $rn = @($rlog | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
                                if ($rn -gt 0) {
                                    $rplural = 's'
                                    if ($rn -eq 1) { $rplural = '' }
                                    $recentReports.Add("$($rc.m) ($rn commit$rplural)")
                                }
                            }
                            if ($recentReports.Count -gt 0) {
                                $out.Add('### Recent activity (24h)')
                                $out.Add($recentReports -join ', ')
                            }
                        }
                    } catch { }
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
