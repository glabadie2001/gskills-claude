# engram-lint.ps1 -- Engram deterministic memory linter (Windows PowerShell 5.1 compatible).
#
# Zero-token static checks over .claude/memory. Twin of engram-lint.sh: both scripts
# must emit byte-identical findings (same order, same messages) for identical inputs.
#
# Usage: engram-lint.ps1 [-Root <repo>] [-Json]
#   -Root  repo root (default: current dir); memory is at <root>/.claude/memory
#   -Json  emit a single-line JSON object CI can parse (stable schema)
#
# Exit code: 1 if any ERROR finding, else 0.
#
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM.

param([string]$Root = '.', [switch]$Json)

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ---------- resolve + normalize root (forward slashes; rel paths are platform-neutral) ----------
$rp = $Root
try { $rp = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path } catch { $rp = $Root }
$root = ($rp -replace '\\', '/')
$root = $root.TrimEnd('/')
$memDir   = "$root/.claude/memory"
$memoryMd = "$memDir/MEMORY.md"

# ---------- findings store ----------
$script:findings = New-Object System.Collections.Generic.List[object]
$script:errCount = 0
$script:warnCount = 0
$script:infoCount = 0
function Add-Finding($level, $check, $file, $message) {
    $o = New-Object PSObject
    $o | Add-Member -MemberType NoteProperty -Name level   -Value $level
    $o | Add-Member -MemberType NoteProperty -Name check   -Value $check
    $o | Add-Member -MemberType NoteProperty -Name file    -Value $file
    $o | Add-Member -MemberType NoteProperty -Name message -Value $message
    $script:findings.Add($o)
    if ($level -eq 'ERROR') { $script:errCount++ }
    elseif ($level -eq 'WARN') { $script:warnCount++ }
    else { $script:infoCount++ }
}

function Count-Lines($path) {
    try { return ([System.IO.File]::ReadAllLines($path)).Count } catch { return 0 }
}

function Rel-Path($full) {
    $f = ($full -replace '\\', '/')
    if ($f.ToLower().StartsWith($root.ToLower())) {
        $s = $f.Substring($root.Length)
        return $s.TrimStart('/')
    }
    return $f
}

function Plural-Commits($n) {
    if ($n -eq 1) { return "$n commit" } else { return "$n commits" }
}

function Json-Escape($s) {
    $x = [string]$s
    $x = $x -replace '\\', '\\'
    $x = $x -replace '"', '\"'
    $x = $x -replace "`t", '\t'
    $x = $x -replace "`r", '\r'
    $x = $x -replace "`n", '\n'
    return $x
}

function Emit-And-Exit {
    if ($Json) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('{"errors":' + $script:errCount + ',"warnings":' + $script:warnCount + ',"findings":[')
        $first = $true
        foreach ($f in $script:findings) {
            if (-not $first) { [void]$sb.Append(',') }
            $first = $false
            [void]$sb.Append('{"level":"' + (Json-Escape $f.level) + '",')
            [void]$sb.Append('"check":"' + (Json-Escape $f.check) + '",')
            [void]$sb.Append('"file":"'  + (Json-Escape $f.file)  + '",')
            [void]$sb.Append('"message":"' + (Json-Escape $f.message) + '"}')
        }
        [void]$sb.Append(']}')
        Write-Output $sb.ToString()
    } else {
        $useColor = $false
        try { if (-not [Console]::IsOutputRedirected) { $useColor = $true } } catch { }
        foreach ($lvl in @('ERROR', 'WARN', 'INFO')) {
            foreach ($f in $script:findings) {
                if ($f.level -ne $lvl) { continue }
                $text = '[' + $f.level + '] ' + $f.check + ': ' + $f.file + ' - ' + $f.message
                if ($useColor) {
                    $col = 'Cyan'
                    if ($lvl -eq 'ERROR') { $col = 'Red' }
                    elseif ($lvl -eq 'WARN') { $col = 'Yellow' }
                    Write-Host $text -ForegroundColor $col
                } else {
                    Write-Output $text
                }
            }
        }
        $summary = "Engram lint: $($script:errCount) error(s), $($script:warnCount) warning(s), $($script:infoCount) info"
        if ($useColor) { Write-Host $summary } else { Write-Output $summary }
    }
    if ($script:errCount -gt 0) { exit 1 } else { exit 0 }
}

# ---------- guard: memory present? ----------
if (-not (Test-Path -LiteralPath $memDir)) {
    Add-Finding 'INFO' 'no-memory' '.claude/memory' 'no Engram memory found at .claude/memory'
    Emit-And-Exit
}

# ---------- git detection ----------
$isGit = $false
try {
    $g = git -C $root rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0 -and "$g" -match 'true') { $isGit = $true }
} catch { }

# ==========================================================================
# The checks below run in a FIXED order; engram-lint.sh reproduces it exactly.
# ==========================================================================

# ---------- 1. no-git INFO ----------
if (-not $isGit) {
    Add-Finding 'INFO' 'no-git' '.claude/memory' 'not a git work tree; git-based checks skipped'
}

# ---------- 2. version-drift ----------
$migPath = "$root/.claude/skills/mem-sync/MIGRATIONS.md"
if (-not (Test-Path -LiteralPath $migPath)) {
    Add-Finding 'INFO' 'version-drift' '.claude/skills/mem-sync/MIGRATIONS.md' 'MIGRATIONS.md not found; version-drift check skipped'
} else {
    $curVer = 0
    try {
        $migText = [System.IO.File]::ReadAllText($migPath)
        $mm = [regex]::Match($migText, 'Current tooling version:\s*(\d+)')
        if ($mm.Success) { $curVer = [int]$mm.Groups[1].Value }
    } catch { }
    $memVer = 1
    $verPath = "$memDir/VERSION"
    if (Test-Path -LiteralPath $verPath) {
        try {
            $vt = ([System.IO.File]::ReadAllText($verPath)).Trim()
            if ($vt -match '^\d+$') { $memVer = [int]$vt }
        } catch { }
    }
    if ($curVer -gt 0 -and $memVer -lt $curVer) {
        Add-Finding 'WARN' 'version-drift' '.claude/memory/VERSION' "memory VERSION $memVer is behind current tooling version $curVer; run /mem-sync"
    }
}

# ---------- 3. MEMORY.md over-budget ----------
if (Test-Path -LiteralPath $memoryMd) {
    $mLines = Count-Lines $memoryMd
    if ($mLines -gt 120) {
        Add-Finding 'WARN' 'over-budget' '.claude/memory/MEMORY.md' "MEMORY.md is $mLines lines (budget 120)"
    }
}

# ---------- enumerate atlas cards + index files ----------
$atlasDir = "$memDir/atlas"
$cardFiles  = @()
$indexFiles = @()
if (Test-Path -LiteralPath $atlasDir) {
    $all = @(Get-ChildItem -LiteralPath $atlasDir -File -Filter '*.md' | Sort-Object Name)
    foreach ($f in $all) {
        if ($f.Name -like '_*') { continue }
        if ($f.Name -like 'INDEX-*') { $indexFiles += $f; continue }
        $cardFiles += $f
    }
}

# ---------- 4. per-card checks ----------
foreach ($card in $cardFiles) {
    $rel = Rel-Path $card.FullName
    $cLines = @()
    try { $cLines = [System.IO.File]::ReadAllLines($card.FullName) } catch { $cLines = @() }

    # parse frontmatter
    $fmEnd = -1
    if ($cLines.Count -ge 1 -and $cLines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $cLines.Count; $i++) {
            if ($cLines[$i].Trim() -eq '---') { $fmEnd = $i; break }
        }
    }
    $module = ''
    $verified = ''
    $cardPaths = @()
    $fmHasComment = $false
    $fmCommentLine = ''
    if ($fmEnd -gt 0) {
        $inPaths = $false
        for ($i = 1; $i -lt $fmEnd; $i++) {
            $l = $cLines[$i]
            if ((-not $fmHasComment) -and ($l.IndexOf('#') -ge 0)) {
                $fmHasComment = $true
                $fmCommentLine = $l.Trim()
            }
            if ($inPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                $cardPaths += $matches[1].Trim('"').Trim("'")
                continue
            }
            $inPaths = $false
            if ($l -match '^module:\s*(.+?)\s*$')   { $module = $matches[1]; continue }
            if ($l -match '^verified:\s*(\S+)')     { $verified = $matches[1]; continue }
            if ($l -match '^paths:\s*$')            { $inPaths = $true; continue }
        }
    }
    if (-not $module) { $module = $card.BaseName }

    # 4a. globs: brace-glob (string) / dead-glob (git)
    foreach ($glob in $cardPaths) {
        if ($glob.IndexOf('{') -ge 0) {
            Add-Finding 'ERROR' 'brace-glob' $rel "paths glob uses brace expansion (git matches nothing): $glob"
            continue
        }
        if ($isGit) {
            $lsOut = @()
            try { $lsOut = @(git -C $root ls-files -- $glob 2>$null) } catch { $lsOut = @() }
            $nonEmpty = @($lsOut | Where-Object { $_ -and $_.Trim().Length -gt 0 })
            if ($nonEmpty.Count -eq 0) {
                Add-Finding 'ERROR' 'dead-glob' $rel "paths glob matches no tracked files: $glob"
            }
        }
    }

    # 4b. verified / stale
    if ((-not $verified) -or ($verified -match '^0+$')) {
        $disp = 'missing'
        if ($verified) { $disp = $verified }
        Add-Finding 'WARN' 'unverified' $rel "card is unverified (verified: $disp)"
    } elseif ($isGit) {
        $objType = ''
        try { $objType = (git -C $root cat-file -t $verified 2>$null) } catch { $objType = '' }
        if ($LASTEXITCODE -ne 0 -or "$objType".Trim() -ne 'commit') {
            Add-Finding 'ERROR' 'bad-verified' $rel "verified '$verified' is not a commit object"
        } elseif ($cardPaths.Count -gt 0) {
            $logLines = @()
            try { $logLines = @(git -C $root log --oneline "$verified..HEAD" -- $cardPaths 2>$null) } catch { $logLines = @() }
            $behind = @($logLines | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
            if ($behind -gt 0) {
                Add-Finding 'WARN' 'stale-card' $rel ("card is " + (Plural-Commits $behind) + " behind HEAD")
            }
        }
    }

    # 4c. frontmatter-comment
    if ($fmHasComment) {
        Add-Finding 'WARN' 'frontmatter-comment' $rel "frontmatter line contains '#' (breaks parsers): $fmCommentLine"
    }

    # 4d. card over-budget
    if ($cLines.Count -gt 60) {
        Add-Finding 'WARN' 'over-budget' $rel ("card is " + $cLines.Count + " lines (budget 60)")
    }

    # 4e. dead-keyfile: first backtick token on each '- ' line inside '## Key files'
    $inKeys = $false
    for ($i = 0; $i -lt $cLines.Count; $i++) {
        $l = $cLines[$i]
        if ($l -match '^##\s') {
            $inKeys = ($l -match '^##\s+Key files\s*$')
            continue
        }
        if ($inKeys -and $l -match '^\s*-\s+`([^`]+)`') {
            $kf = $matches[1].Trim()
            $kf = $kf.TrimEnd('/')
            if ($kf -match '[\*\?\{]') { continue }   # glob-ish, not a concrete path
            if ($kf.Length -eq 0) { continue }
            $kfFull = "$root/$kf"
            if (-not (Test-Path -LiteralPath $kfFull)) {
                Add-Finding 'ERROR' 'dead-keyfile' $rel "Key files path does not exist: $kf"
            }
        }
    }
}

# ---------- 5. INDEX-* over-budget ----------
foreach ($idx in $indexFiles) {
    $rel = Rel-Path $idx.FullName
    $n = Count-Lines $idx.FullName
    if ($n -gt 60) {
        Add-Finding 'WARN' 'over-budget' $rel "index is $n lines (budget 60)"
    }
}

# ---------- build wikilink target set (all non-template *.md basenames under memDir) ----------
$targetNames = New-Object 'System.Collections.Generic.HashSet[string]'
$scanFiles = @()
if (Test-Path -LiteralPath $memDir) {
    $mdAll = @(Get-ChildItem -LiteralPath $memDir -Recurse -File -Filter '*.md')
    foreach ($f in $mdAll) {
        if ($f.Name -like '_*') { continue }
        [void]$targetNames.Add($f.BaseName)
        $scanFiles += $f
    }
}
# stable scan order by relative path
$scanFiles = @($scanFiles | Sort-Object { Rel-Path $_.FullName })

function Resolve-Link($t) {
    $tt = $t.Trim()
    if ($tt -eq '') { return $true }
    if ($tt -match '^adr-(.+)$') {
        $num = $matches[1]
        if ($targetNames.Contains($tt)) { return $true }
        foreach ($n in $targetNames) { if ($n.StartsWith($num + '-')) { return $true } }
        return $false
    }
    if ($targetNames.Contains($tt)) { return $true }
    return $false
}

# ---------- 6. broken-wikilink ----------
$bt = [char]0x60
$codePattern = "$bt[^$bt]*$bt"
foreach ($f in $scanFiles) {
    $rel = Rel-Path $f.FullName
    $lines = @()
    try { $lines = [System.IO.File]::ReadAllLines($f.FullName) } catch { continue }
    foreach ($line in $lines) {
        $scan = [regex]::Replace($line, $codePattern, ' ')
        $mm = [regex]::Matches($scan, '\[\[([^\]]+)\]\]')
        foreach ($m in $mm) {
            $inner = $m.Groups[1].Value
            $target = $inner
            $bar = $target.IndexOf('|'); if ($bar -ge 0) { $target = $target.Substring(0, $bar) }
            $hsh = $target.IndexOf('#'); if ($hsh -ge 0) { $target = $target.Substring(0, $hsh) }
            $target = $target.Trim()
            if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') { continue }
            if (-not (Resolve-Link $target)) {
                Add-Finding 'ERROR' 'broken-wikilink' $rel "wikilink [[$target]] resolves to nothing"
            }
        }
    }
}

# ---------- 7. unsigned-entry (journal/YYYY-MM-DD.md headlines) ----------
$journalDir = "$memDir/journal"
if (Test-Path -LiteralPath $journalDir) {
    $jf = @(Get-ChildItem -LiteralPath $journalDir -File -Filter '*.md' |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}\.md$' } |
        Sort-Object Name)
    foreach ($j in $jf) {
        $rel = Rel-Path $j.FullName
        $lines = @()
        try { $lines = [System.IO.File]::ReadAllLines($j.FullName) } catch { continue }
        foreach ($line in $lines) {
            if ($line -match '^##\s') {
                $trim = $line.TrimEnd()
                if ($trim -notmatch '\[[^\]]+\]\s*$') {
                    Add-Finding 'INFO' 'unsigned-entry' $rel "journal headline lacks [model-id] signature: $trim"
                }
            }
        }
    }
}

# ---------- 8. architecture overview (same frontmatter contract as a card) ----------
$archFile = "$memDir/architecture.md"
if (Test-Path -LiteralPath $archFile) {
    $rel = Rel-Path $archFile
    $aLines = @()
    try { $aLines = [System.IO.File]::ReadAllLines($archFile) } catch { $aLines = @() }

    # parse frontmatter
    $fmEnd = -1
    if ($aLines.Count -ge 1 -and $aLines[0].Trim() -eq '---') {
        for ($i = 1; $i -lt $aLines.Count; $i++) {
            if ($aLines[$i].Trim() -eq '---') { $fmEnd = $i; break }
        }
    }
    $verified = ''
    $archPaths = @()
    if ($fmEnd -gt 0) {
        $inPaths = $false
        for ($i = 1; $i -lt $fmEnd; $i++) {
            $l = $aLines[$i]
            if ($inPaths -and $l -match '^\s+-\s*(.+?)\s*$') {
                $archPaths += $matches[1].Trim('"').Trim("'")
                continue
            }
            $inPaths = $false
            if ($l -match '^verified:\s*(\S+)')     { $verified = $matches[1]; continue }
            if ($l -match '^paths:\s*$')            { $inPaths = $true; continue }
        }
    }

    # 8a. globs: brace-glob (string) / dead-glob (git)
    foreach ($glob in $archPaths) {
        if ($glob.IndexOf('{') -ge 0) {
            Add-Finding 'ERROR' 'brace-glob' $rel "paths glob uses brace expansion (git matches nothing): $glob"
            continue
        }
        if ($isGit) {
            $lsOut = @()
            try { $lsOut = @(git -C $root ls-files -- $glob 2>$null) } catch { $lsOut = @() }
            $nonEmpty = @($lsOut | Where-Object { $_ -and $_.Trim().Length -gt 0 })
            if ($nonEmpty.Count -eq 0) {
                Add-Finding 'ERROR' 'dead-glob' $rel "paths glob matches no tracked files: $glob"
            }
        }
    }

    # 8b. verified / stale (Live diagram only — the Target never goes stale by commit)
    if ((-not $verified) -or ($verified -match '^0+$')) {
        $disp = 'missing'
        if ($verified) { $disp = $verified }
        Add-Finding 'WARN' 'unverified' $rel "Live diagram is unverified (verified: $disp)"
    } elseif ($isGit) {
        $objType = ''
        try { $objType = (git -C $root cat-file -t $verified 2>$null) } catch { $objType = '' }
        if ($LASTEXITCODE -ne 0 -or "$objType".Trim() -ne 'commit') {
            Add-Finding 'ERROR' 'bad-verified' $rel "verified '$verified' is not a commit object"
        } elseif ($archPaths.Count -gt 0) {
            $logLines = @()
            try { $logLines = @(git -C $root log --oneline "$verified..HEAD" -- $archPaths 2>$null) } catch { $logLines = @() }
            $behind = @($logLines | Where-Object { $_ -and $_.Trim().Length -gt 0 }).Count
            if ($behind -gt 0) {
                Add-Finding 'WARN' 'stale-arch' $rel ("Live diagram is " + (Plural-Commits $behind) + " behind HEAD")
            }
        }
    }

    # 8c. over-budget
    if ($aLines.Count -gt 120) {
        Add-Finding 'WARN' 'over-budget' $rel ("architecture.md is " + $aLines.Count + " lines (budget 120)")
    }
}

# ---------- 9. dead-mdlink (relative markdown links must resolve on disk) ----------
# ERROR under sweeps/ (an unlinked/broken artifact breaks the campaign hierarchy),
# WARN elsewhere. Skipped: sweeps/artifacts/ (frozen historical records), #anchors,
# and any target containing ':' (URL schemes, drive letters, file.ts:63 citations);
# inline code is stripped.
foreach ($f in $scanFiles) {
    $rel = Rel-Path $f.FullName
    if ($rel -like '*/sweeps/artifacts/*') { continue }
    $fdir = ($f.DirectoryName -replace '\\', '/')
    $lines = @()
    try { $lines = [System.IO.File]::ReadAllLines($f.FullName) } catch { continue }
    foreach ($line in $lines) {
        $scan = [regex]::Replace($line, $codePattern, ' ')
        $mm = [regex]::Matches($scan, '\]\(([^)\s]+)\)')
        foreach ($m in $mm) {
            $target = $m.Groups[1].Value
            if ($target.StartsWith('#')) { continue }
            if ($target.IndexOf(':') -ge 0) { continue }
            $hsh = $target.IndexOf('#'); if ($hsh -ge 0) { $target = $target.Substring(0, $hsh) }
            if ($target.Length -eq 0) { continue }
            if (-not (Test-Path -LiteralPath "$fdir/$target")) {
                if ($rel -like '*/sweeps/*') {
                    Add-Finding 'ERROR' 'dead-mdlink' $rel "relative link resolves to nothing: $target"
                } else {
                    Add-Finding 'WARN' 'dead-mdlink' $rel "relative link resolves to nothing: $target"
                }
            }
        }
    }
}

# ==========================================================================
# Output
# ==========================================================================
Emit-And-Exit
