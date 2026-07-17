# engram-statusline.ps1 -- Engram status line for Claude Code (Windows PowerShell
# 5.1 compatible twin of engram-statusline.sh).
#
# Claude Code pipes status-line JSON to stdin and renders whatever this prints
# at the bottom of the UI: open task counts, atlas freshness, journal recency
# for the CURRENT project. Prints nothing in projects without Engram.
#
# On Windows, Claude Code runs status line commands through Git Bash when it is
# installed, so the bash twin is the default registration. Use THIS script only
# when Git Bash is absent, by swapping the user-settings statusLine command to:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/<you>/.claude/engram-statusline.ps1"
#
# The atlas staleness pass runs git per card, so counts are cached in $env:TEMP
# keyed by project; the cache invalidates when HEAD moves, the card set changes,
# or any card file is edited.
#
# Failure philosophy: any failure renders nothing (or silently drops that
# segment). The script always exits 0.
#
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM;
# unicode glyphs are built from codepoints below.

$ErrorActionPreference = 'SilentlyContinue'

try {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

    # ---------- read stdin JSON, resolve project root ----------
    $root = ''
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw -and $raw.Trim().Length -gt 0) {
            $payload = $raw | ConvertFrom-Json
            if ($payload.workspace -and $payload.workspace.PSObject.Properties['project_dir']) {
                $root = [string]$payload.workspace.project_dir
            }
            if ((-not $root) -and $payload.PSObject.Properties['cwd']) {
                $root = [string]$payload.cwd
            }
        }
    } catch { }
    if (-not $root) { $root = $env:CLAUDE_PROJECT_DIR }
    if (-not $root) { $root = (Get-Location).Path }

    $memDir = Join-Path $root '.claude\memory'
    $memoryMd = Join-Path $memDir 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $memoryMd)) { exit 0 }   # no Engram -> blank

    $esc = [string][char]27
    $GRN = "$esc[32m"; $YEL = "$esc[33m"; $DIM = "$esc[90m"; $RST = "$esc[0m"
    $BRAIN = [char]::ConvertFromUtf32(0x1F9E0)   # brain emoji
    $BAR = [string][char]0x2502                  # box-drawing vertical bar
    $DOT = [string][char]0x00B7                  # middle dot
    $PEN = [string][char]0x270E                  # pencil
    $CHK = [string][char]0x2713                  # check mark

    # ---------- empty memory: single nudge ----------
    $memoryText = ''
    try { $memoryText = [System.IO.File]::ReadAllText($memoryMd) } catch { }
    if ($memoryText.IndexOf('STATUS: EMPTY') -ge 0) {
        Write-Output ($BRAIN + ' ' + $YEL + 'memory empty ' + $DOT + ' run /mem-init' + $RST)
        exit 0
    }

    # ---------- tasks: count top-level bullets under ## Now / ## Next ----------
    $nowN = 0; $nextN = 0
    try {
        $tasksPath = Join-Path $memDir 'tasks.md'
        if (Test-Path -LiteralPath $tasksPath) {
            $sect = ''
            foreach ($l in [System.IO.File]::ReadAllLines($tasksPath)) {
                if ($l -like '## Now*') { $sect = 'now'; continue }
                if ($l -like '## Next*') { $sect = 'next'; continue }
                if ($l -like '## *') { $sect = 'other'; continue }
                if ($l -like '- *' -or $l -like '* *') {
                    if ($sect -eq 'now') { $nowN++ }
                    elseif ($sect -eq 'next') { $nextN++ }
                }
            }
        }
    } catch { }
    if (($nowN + $nextN) -gt 0) {
        $tasksSeg = "$nowN now$DIM $DOT $RST$nextN next"
    } else {
        $tasksSeg = $DIM + 'no tasks' + $RST
    }

    # ---------- atlas freshness (cached; recompute only when git state moves) ----------
    $atlasSeg = ''
    try {
        $isGit = $false
        $gitOut = git -C $root rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -eq 0 -and "$gitOut" -match 'true') { $isGit = $true }
        if ($isGit) {
            $headSha = [string](git -C $root rev-parse HEAD 2>$null)
            $atlasDir = Join-Path $memDir 'atlas'
            $cards = @()
            if (Test-Path -LiteralPath $atlasDir) {
                $cards = @(Get-ChildItem -LiteralPath $atlasDir -File -Filter '*.md' |
                    Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
            }
            if ($headSha -and $cards.Count -gt 0) {
                $md5 = [System.Security.Cryptography.MD5]::Create()
                $listBytes = [System.Text.Encoding]::UTF8.GetBytes(($cards | ForEach-Object { $_.Name }) -join "`n")
                $listSum = [System.BitConverter]::ToString($md5.ComputeHash($listBytes)).Replace('-', '').Substring(0, 12)
                $key = "$headSha $listSum"
                $rootSum = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($root))).Replace('-', '').Substring(0, 12)
                $cache = Join-Path $env:TEMP "engram-statusline-$rootSum.cache"

                $counts = $null
                if (Test-Path -LiteralPath $cache) {
                    $cLines = @([System.IO.File]::ReadAllLines($cache))
                    if ($cLines.Count -ge 2 -and $cLines[0] -eq $key) {
                        $cacheTime = (Get-Item -LiteralPath $cache).LastWriteTimeUtc
                        $edited = $false
                        foreach ($card in $cards) {
                            if ($card.LastWriteTimeUtc -gt $cacheTime) { $edited = $true; break }
                        }
                        if (-not $edited) { $counts = $cLines[1] }
                    }
                }
                if ($null -eq $counts) {
                    $checked = 0; $stale = 0
                    foreach ($card in $cards) {
                        try {
                            $cl = [System.IO.File]::ReadAllLines($card.FullName)
                            if ($cl.Count -lt 2 -or $cl[0].Trim() -ne '---') { continue }
                            $verified = ''; $cardPaths = @(); $inPaths = $false
                            for ($i = 1; $i -lt $cl.Count; $i++) {
                                $l = $cl[$i]
                                if ($l.Trim() -eq '---') { break }
                                if ($inPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                                    $cardPaths += $matches[1].Trim('"').Trim("'")
                                    continue
                                }
                                $inPaths = $false
                                if ($l -match '^verified:\s*(\S+)') { $verified = $matches[1]; continue }
                                if ($l -match '^paths:\s*$') { $inPaths = $true; continue }
                            }
                            if ($cardPaths.Count -eq 0) { continue }   # malformed card: skip silently
                            $checked++
                            # Unknown baseline counts as stale: the card needs /mem-sync either way.
                            if ((-not $verified) -or ($verified -match '^0+$')) { $stale++; continue }
                            $objType = (git -C $root cat-file -t $verified 2>$null)
                            if ($LASTEXITCODE -ne 0 -or "$objType".Trim() -ne 'commit') { $stale++; continue }
                            $logLines = @(git -C $root log --oneline "$verified..HEAD" -- $cardPaths 2>$null)
                            if ($LASTEXITCODE -ne 0) { $stale++; continue }
                            $behind = @($logLines | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
                            if ($behind -gt 0) { $stale++ }
                        } catch { }
                    }
                    $counts = "$checked $stale"
                    try { [System.IO.File]::WriteAllLines($cache, @($key, $counts)) } catch { }
                }
                $parts = $counts -split ' '
                $nChecked = [int]$parts[0]; $nStale = [int]$parts[1]
                if ($nChecked -gt 0) {
                    if ($nStale -gt 0) {
                        $atlasSeg = $YEL + "atlas $nStale/$nChecked stale" + $RST
                    } else {
                        $atlasSeg = $GRN + "atlas $nChecked$CHK" + $RST
                    }
                }
            }
        }
    } catch { }

    # ---------- journal recency: newest journal/YYYY-MM-DD.md ----------
    $jSeg = ''
    try {
        $journalDir = Join-Path $memDir 'journal'
        $jFiles = @()
        if (Test-Path -LiteralPath $journalDir) {
            $jFiles = @(Get-ChildItem -LiteralPath $journalDir -File -Filter '*.md' |
                Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
        }
        if ($jFiles.Count -eq 0) {
            $jSeg = $YEL + $PEN + ' none' + $RST
        } else {
            $jDate = $jFiles[-1].BaseName
            if ($jDate -match '^\d{4}-\d{2}-\d{2}$') {
                $d = [datetime]::ParseExact($jDate, 'yyyy-MM-dd', $null)
                $days = ([datetime]::Today - $d.Date).Days
                if ($days -le 0) { $jSeg = $GRN + $PEN + ' today' + $RST }
                elseif ($days -ge 3) { $jSeg = $YEL + $PEN + " ${days}d" + $RST }
                else { $jSeg = $PEN + " ${days}d" }
            }
        }
    } catch { }

    # ---------- assemble ----------
    $out = $BRAIN + ' ' + $tasksSeg
    if ($atlasSeg) { $out = $out + ' ' + $DIM + $BAR + $RST + ' ' + $atlasSeg }
    if ($jSeg) { $out = $out + ' ' + $DIM + $BAR + $RST + ' ' + $jSeg }
    Write-Output $out
    exit 0
} catch {
    exit 0
}
