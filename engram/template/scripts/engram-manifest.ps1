# engram-manifest.ps1 -- Engram footprint-manifest tool (Windows PowerShell 5.1
# compatible twin of engram-manifest.sh). Both twins must emit byte-identical
# output for identical inputs.
#
# A card's manifest (atlas/<module>.manifest) is the set of tracked files under
# the card's `paths:` globs AT THE COMMIT the card was last verified against
# (frontmatter `verified:`): one "<40-hex blob sha> <path>" line per file,
# ordinal-sorted by path, LF endings. Manifests are SCRIPT-GENERATED ONLY (the
# linter recomputes them and ERRORs on any mismatch) and state only COMMITTED
# content: they are written from `git ls-tree -r <verified>`, never from the
# working tree -- so a manifest can never vouch for code that isn't in a commit.
#
# Usage: engram-manifest.ps1 <status|update> [--root <repo>] [--card <module>]...
#   (see engram-manifest.sh header for the status/update output contract)
#
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM.

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ---------- args (manual parse: the bash twin dispatches --flags verbatim) ----------
$Mode = ''
$ArgRoot = '.'
$OnlyCards = @()
$i = 0
while ($i -lt $args.Count) {
    $a = [string]$args[$i]
    if ($a -eq 'status' -or $a -eq 'update') { $Mode = $a; $i++ }
    elseif ($a -eq '--root' -and ($i + 1) -lt $args.Count) { $ArgRoot = [string]$args[$i + 1]; $i += 2 }
    elseif ($a -eq '--card' -and ($i + 1) -lt $args.Count) { $OnlyCards += [string]$args[$i + 1]; $i += 2 }
    else { $i++ }
}
if ($Mode -ne 'status' -and $Mode -ne 'update') {
    [Console]::Error.WriteLine('usage: engram-manifest.ps1 <status|update> [--root <repo>] [--card <module>]...')
    exit 2
}

# ---------- resolve + normalize root (same pin/probe order as the linter) ----------
$rp = $ArgRoot
try { $rp = (Resolve-Path -LiteralPath $ArgRoot -ErrorAction Stop).Path } catch { $rp = $ArgRoot }
$root = ($rp -replace '\\', '/')
$root = $root.TrimEnd('/')
if (-not (Test-Path -LiteralPath "$root/.claude/memory/MEMORY.md")) {
    $resolved = $null
    $pinPath = "$root/.claude/engram-root"
    if (Test-Path -LiteralPath $pinPath) {
        try {
            $pinLines = [System.IO.File]::ReadAllLines($pinPath)
            $pinLine = ''
            foreach ($pl in $pinLines) {
                $t = $pl.TrimEnd("`r").Trim()
                if ($t.Length -gt 0) { $pinLine = $t; break }
            }
            if ($pinLine) {
                $cand = ("$root/$pinLine" -replace '\\', '/').TrimEnd('/')
                if (Test-Path -LiteralPath "$cand/.claude/memory/MEMORY.md") { $resolved = $cand }
            }
        } catch { }
    }
    if (-not $resolved) {
        $subs = @()
        try { $subs = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop | Sort-Object Name) } catch { $subs = @() }
        foreach ($d in $subs) {
            $cand = ($d.FullName -replace '\\', '/').TrimEnd('/')
            if (Test-Path -LiteralPath "$cand/.claude/memory/MEMORY.md") { $resolved = $cand; break }
        }
    }
    if ($resolved) { $root = $resolved }
}

$atlasDir = "$root/.claude/memory/atlas"
if (-not (Test-Path -LiteralPath $atlasDir -PathType Container)) { exit 1 }
& git -C $root rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }

# ---------- enumerate cards (ordinal-sorted; skip _*.md and INDEX-*.md) ----------
$cardFiles = @()
try {
    $all = @(Get-ChildItem -LiteralPath $atlasDir -Filter '*.md' -File -ErrorAction Stop)
    $names = @()
    foreach ($f in $all) { $names += $f.Name }
    [Array]::Sort($names, [System.StringComparer]::Ordinal)
    foreach ($n in $names) {
        if ($n.StartsWith('_') -or $n.StartsWith('INDEX-')) { continue }
        $cardFiles += "$atlasDir/$n"
    }
} catch { $cardFiles = @() }

# ---------- helpers ----------
function Parse-Card($cardPath) {
    # returns @{ Module=..; Verified=..; Paths=@(..) }
    $module = [System.IO.Path]::GetFileNameWithoutExtension($cardPath)
    $verified = ''
    $paths = @()
    $lines = @()
    try { $lines = [System.IO.File]::ReadAllLines($cardPath) } catch { $lines = @() }
    if ($lines.Count -gt 0 -and $lines[0] -match '^---\s*$') {
        $inPaths = $false
        for ($li = 1; $li -lt $lines.Count; $li++) {
            $l = $lines[$li]
            if ($l -match '^---\s*$') { break }
            if ($l -match '^verified:\s*(.*)$') {
                if (-not $verified) { $verified = (($Matches[1].Trim()) -split '\s+')[0] }
                $inPaths = $false
            }
            elseif ($l -match '^paths:\s*$') { $inPaths = $true }
            elseif ($inPaths -and $l -match '^\s+-\s*(.*)$') {
                $g = $Matches[1].Trim().Trim('"').Trim("'")
                if ($g) { $paths += $g }
            }
            else { $inPaths = $false }
        }
    }
    return @{ Module = $module; Verified = $verified; Paths = $paths }
}

function Globs-To-Regex($globs) {
    # One regex matching git-default pathspec semantics: * and ? cross '/',
    # a wildcard-free glob also matches as a dir prefix. Mirrors the bash twin.
    $parts = @()
    foreach ($g in $globs) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $g.ToCharArray()) {
            $c = [string]$ch
            if ($c -eq '*') { [void]$sb.Append('.*') }
            elseif ($c -eq '?') { [void]$sb.Append('.') }
            elseif ('.+()|^$'.Contains($c) -or $c -eq '{' -or $c -eq '}' -or $c -eq '\') {
                [void]$sb.Append('\').Append($c)
            }
            else { [void]$sb.Append($c) }
        }
        $parts += $sb.ToString()
    }
    if ($parts.Count -eq 0) { return $null }
    $pattern = '^(' + ($parts -join '|') + ')(/.*)?$'
    return New-Object System.Text.RegularExpressions.Regex($pattern)
}

function Is-Attested($verified) {
    if (-not $verified) { return $false }
    if ($verified -match '^0+$' -or $verified.StartsWith('0000000')) { return $false }
    return $true
}

function Plural($n, $singular, $plural) {
    if ($n -eq 1) { return "$n $singular" } else { return "$n $plural" }
}

function Manifest-Lines-At($sha, $re) {
    # "sha path" lines from git ls-tree at $sha, ordinal path order. ls-tree
    # path arguments are literal prefixes, NOT pathspec globs -- so list the
    # whole tree and filter with the same in-process matcher status uses
    # (identical semantics by construction).
    $raw = @(& git -C $root -c core.quotepath=false ls-tree -r $sha 2>$null)
    if ($LASTEXITCODE -ne 0) { return @() }
    $pairs = @{}
    foreach ($line in $raw) {
        if (-not $line) { continue }
        $ti = $line.IndexOf("`t")
        if ($ti -lt 1) { continue }
        $p = $line.Substring($ti + 1)
        if (-not $re.IsMatch($p)) { continue }
        $meta = $line.Substring(0, $ti) -split '\s+'
        if ($meta.Count -lt 3) { continue }
        $pairs[$p] = $meta[2]
    }
    $keys = @($pairs.Keys)
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    $out = @()
    foreach ($k in $keys) { $out += ($pairs[$k] + ' ' + $k) }
    return $out
}

# ==========================================================================
# status
# ==========================================================================
if ($Mode -eq 'status') {
    $headTree = @(& git -C $root -c core.quotepath=false ls-tree -r HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $headTree = @() }
    $porc = @(& git -C $root -c core.quotepath=false status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { $porc = @() }

    # Pre-parse HEAD tree into (path -> sha).
    $headMap = @{}
    foreach ($line in $headTree) {
        if (-not $line) { continue }
        $ti = $line.IndexOf("`t")
        if ($ti -lt 1) { continue }
        $meta = $line.Substring(0, $ti) -split '\s+'
        if ($meta.Count -lt 3) { continue }
        $headMap[$line.Substring($ti + 1)] = $meta[2]
    }

    # Uncommitted paths (staged, unstaged, untracked); renames keep the new name.
    $dirtyPaths = @()
    foreach ($line in $porc) {
        if (-not $line -or $line.Length -lt 4) { continue }
        $p = $line.Substring(3)
        $ai = $p.IndexOf(' -> ')
        if ($ai -ge 0) { $p = $p.Substring($ai + 4) }
        $p = $p.Trim('"')
        if ($p) { $dirtyPaths += $p }
    }

    $dirtyFiles = @{}
    $dirtyCards = 0
    $out = New-Object System.Collections.Generic.List[string]

    foreach ($card in $cardFiles) {
        $pc = Parse-Card $card
        if ($pc.Paths.Count -eq 0) { continue }    # malformed card: skip silently
        $re = Globs-To-Regex $pc.Paths
        if (-not $re) { continue }
        $module = $pc.Module
        $mf = "$atlasDir/$module.manifest"

        # Dirty scan for this footprint (state-independent aggregate).
        $cardDirty = $false
        foreach ($dp in $dirtyPaths) {
            if ($re.IsMatch($dp)) { $cardDirty = $true; $dirtyFiles[$dp] = $true }
        }
        if ($cardDirty) { $dirtyCards++ }

        if (-not (Is-Attested $pc.Verified)) {
            [void]$out.Add("ASSUMED`t$module`tnever verified")
            continue
        }

        if (-not (Test-Path -LiteralPath $mf)) {
            # Transitional: attested card, no sidecar -- fall back to the range check.
            $objType = (& git -C $root cat-file -t $pc.Verified 2>$null)
            if ($LASTEXITCODE -ne 0 -or "$objType" -ne 'commit') {
                [void]$out.Add("NOMANIFEST`t$module`tunknown baseline")
            } else {
                $range = $pc.Verified + '..HEAD'
                $gitArgs = @('-C', $root, 'log', '--oneline', $range, '--') + $pc.Paths
                $logLines = @(& git @gitArgs 2>$null)
                if ($LASTEXITCODE -ne 0) { $logLines = @() }
                $behind = 0
                foreach ($ll in $logLines) { if ($ll) { $behind++ } }
                if ($behind -gt 0) {
                    [void]$out.Add("NOMANIFEST`t$module`t" + (Plural $behind 'commit' 'commits') + ' behind')
                } else {
                    [void]$out.Add("NOMANIFEST`t$module`tno manifest yet")
                }
            }
            continue
        }

        # Set-compare: manifest (footprint at attestation) vs tracked tree at HEAD.
        $man = @{}
        $mfLines = @()
        try { $mfLines = [System.IO.File]::ReadAllLines($mf) } catch { $mfLines = @() }
        foreach ($ml in $mfLines) {
            if ($ml -and $ml.Length -ge 42) { $man[$ml.Substring(41)] = $ml.Substring(0, 40) }
        }
        $cur = @{}
        foreach ($hp in $headMap.Keys) {
            if ($re.IsMatch($hp)) { $cur[$hp] = $headMap[$hp] }
        }
        $chg = 0; $add = 0; $rem = 0
        foreach ($p in $man.Keys) {
            if (-not $cur.ContainsKey($p)) { $rem++ }
            elseif ($man[$p] -cne $cur[$p]) { $chg++ }
        }
        foreach ($p in $cur.Keys) {
            if (-not $man.ContainsKey($p)) { $add++ }
        }
        if (($chg + $add + $rem) -eq 0) {
            [void]$out.Add("VERIFIED`t$module`t-")
        } else {
            $parts = @()
            if ($chg -gt 0) { $parts += "$chg changed" }
            if ($add -gt 0) { $parts += "$add added" }
            if ($rem -gt 0) { $parts += "$rem removed" }
            [void]$out.Add("DRIFTED`t$module`t" + ($parts -join ', '))
        }
    }

    if ($dirtyCards -gt 0) {
        $nDirty = $dirtyFiles.Count
        [void]$out.Add("DIRTY`t-`t" + (Plural $nDirty 'file' 'files') + ' across ' + (Plural $dirtyCards 'card' 'cards'))
    }
    foreach ($l in $out) { Write-Output $l }
    exit 0
}

# ==========================================================================
# update
# ==========================================================================
foreach ($card in $cardFiles) {
    $pc = Parse-Card $card
    $module = $pc.Module
    if ($OnlyCards.Count -gt 0 -and ($OnlyCards -cnotcontains $module)) { continue }
    if ($pc.Paths.Count -eq 0) { continue }    # malformed card: skip silently
    $re = Globs-To-Regex $pc.Paths
    if (-not $re) { continue }
    $mf = "$atlasDir/$module.manifest"

    if (-not (Is-Attested $pc.Verified)) {
        Write-Output "SKIP`t$module`tnever verified"
        continue
    }
    $objType = (& git -C $root cat-file -t $pc.Verified 2>$null)
    if ($LASTEXITCODE -ne 0 -or "$objType" -ne 'commit') {
        Write-Output ("SKIP`t$module`tbad verified: " + $pc.Verified)
        continue
    }

    $newLines = @(Manifest-Lines-At $pc.Verified $re)
    $newContent = ($newLines -join "`n")
    $oldContent = $null
    if (Test-Path -LiteralPath $mf) {
        try { $oldContent = [System.IO.File]::ReadAllText($mf) } catch { $oldContent = $null }
    }
    if ($null -ne $oldContent -and $oldContent.TrimEnd("`n") -ceq $newContent) {
        Write-Output "OK`t$module`tunchanged"
        continue
    }
    if ($newLines.Count -gt 0) {
        [System.IO.File]::WriteAllText($mf, $newContent + "`n")
    } else {
        [System.IO.File]::WriteAllText($mf, '')
    }
    Write-Output ("WROTE`t$module`t" + (Plural $newLines.Count 'file' 'files'))
}

# Orphan manifests (card deleted): prune only on full runs.
if ($OnlyCards.Count -eq 0) {
    $mfs = @()
    try {
        $mfAll = @(Get-ChildItem -LiteralPath $atlasDir -Filter '*.manifest' -File -ErrorAction Stop)
        $mfNames = @()
        foreach ($f in $mfAll) { $mfNames += $f.Name }
        [Array]::Sort($mfNames, [System.StringComparer]::Ordinal)
        $mfs = $mfNames
    } catch { $mfs = @() }
    foreach ($n in $mfs) {
        $base = $n.Substring(0, $n.Length - '.manifest'.Length)
        if (-not (Test-Path -LiteralPath "$atlasDir/$base.md")) {
            try { Remove-Item -LiteralPath "$atlasDir/$n" -Force -ErrorAction Stop } catch { }
            Write-Output "PRUNE`t$base`tno card"
        }
    }
}
exit 0
