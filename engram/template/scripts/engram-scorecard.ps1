# engram-scorecard.ps1 -- Engram deterministic scorecard generator (Windows PowerShell 5.1 compatible).
#
# Zero-token metrics: reads .claude/memory/metrics/events.jsonl (the log DB) and
# regenerates .claude/memory/metrics/scorecard.md. Twin of engram-scorecard.sh:
# both scripts must emit a byte-identical scorecard for identical inputs (the only
# input besides the log is today's date, for the 30-day window).
#
# Stat definitions (shared with the .sh twin -- keep in sync):
#   hit rate      = (hit + verified) / recalls, percent, floor(x+0.5) rounding
#   backfill rate = misses with non-null "backfilled" / misses
#   means         = over events where the key is PRESENT (absent key = event drops
#                   out of that stat entirely; never counted as 0), floor(x*10+0.5)/10
#   index-miss    = share of recalls with mem_greps > 0, over recalls carrying the key
#   benefit       = mean files_read on misses minus on hits, per hit, x hit count
#   repeat misses = EXACT duplicates of normalized miss questions only; semantic
#                   near-duplicate judgment stays in /mem-sync (model work)
#
# Usage: engram-scorecard.ps1 [-Root <repo>]
#   -Root  repo root (default: current dir); resolves satellite pins like the linter
#
# Exit code: 0 on success (including "no events yet"), 1 if the memory dir is missing.
#
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM.

param([string]$Root = '.')

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ---------- resolve + normalize root (same rung order as engram-lint) ----------
$rp = $Root
try { $rp = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path } catch { $rp = $Root }
$root = ($rp -replace '\\', '/').TrimEnd('/')

if (-not (Test-Path -LiteralPath "$root/.claude/memory/MEMORY.md")) {
    $resolved = $null
    $pinPath = "$root/.claude/engram-root"
    if (Test-Path -LiteralPath $pinPath) {
        $pin = (Get-Content -LiteralPath $pinPath -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($pin) { $pin = $pin.Trim() }
        if ($pin -and (Test-Path -LiteralPath "$root/$pin/.claude/memory/MEMORY.md")) { $resolved = "$root/$pin" }
    }
    if (-not $resolved) {
        $hits = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Where-Object { Test-Path -LiteralPath ($_.FullName + '/.claude/memory/MEMORY.md') })
        if ($hits.Count -ge 1) { $resolved = ($hits[0].FullName -replace '\\', '/') }
    }
    if ($resolved) { $root = $resolved.TrimEnd('/') }
}

$memdir = "$root/.claude/memory"
if (-not (Test-Path -LiteralPath "$memdir/MEMORY.md")) {
    Write-Output "engram-scorecard: no memory at $memdir"
    exit 1
}
$eventsPath = "$memdir/metrics/events.jsonl"
$outPath    = "$memdir/metrics/scorecard.md"

# ---------- shared rounding (identical to the awk twin) ----------
function FloorX([double]$x) { return [math]::Floor($x) }
function Fmt1([double]$x) {
    $v = (FloorX ($x * 10 + 0.5)) / 10
    return $v.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture)
}
function Pct([double]$num, [double]$den) {
    $p = FloorX ($num * 100 / $den + 0.5)
    return "$($p)%"
}

# ---------- parse events ----------
$recalls = @()
$syncs   = @()
if (Test-Path -LiteralPath $eventsPath) {
    foreach ($line in (Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue)) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $o = $null
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if (-not $o) { continue }
        if ($o.t -eq 'recall') { $recalls += ,$o }
        elseif ($o.t -eq 'sync') { $syncs += ,$o }
    }
}

function HasKey($obj, [string]$key) { return ($obj.PSObject.Properties.Name -contains $key) }
function MeanKey($list, [string]$key) {
    $vals = @()
    foreach ($e in $list) {
        if ((HasKey $e $key) -and ($null -ne $e.$key)) { $vals += ,([double]$e.$key) }
    }
    if ($vals.Count -eq 0) { return $null }
    $s = 0.0; foreach ($v in $vals) { $s += $v }
    return $s / $vals.Count
}

function RetrievalRow([string]$label, $subset) {
    $n = $subset.Count
    $hit = 0; $ver = 0; $miss = 0; $bf = 0
    foreach ($e in $subset) {
        if ($e.outcome -eq 'hit') { $hit++ }
        elseif ($e.outcome -eq 'verified') { $ver++ }
        elseif ($e.outcome -eq 'miss') {
            $miss++
            if ((HasKey $e 'backfilled') -and ($null -ne $e.backfilled)) { $bf++ }
        }
    }
    $hr = '--'; if ($n -gt 0) { $hr = Pct ($hit + $ver) $n }
    $br = '--'; if ($miss -gt 0) { $br = Pct $bf $miss }
    $mf = '--'
    $m = MeanKey $subset 'files_read'
    if ($null -ne $m) { $mf = Fmt1 $m }
    return "| $label | $n | $hit | $ver | $miss | $hr | $br | $mf |"
}

# ---------- windows ----------
$cutoff = (Get-Date).AddDays(-30).ToString('yyyy-MM-dd')
$recent = @($recalls | Where-Object { $_.ts -and $_.ts.Length -ge 10 -and ([string]::CompareOrdinal($_.ts.Substring(0, 10), $cutoff) -ge 0) })

# ---------- index lines (fixed overhead, counted live) ----------
$idxText = [System.IO.File]::ReadAllText("$memdir/MEMORY.md")
$idxLines = ([regex]::Matches($idxText, "`n")).Count

# ---------- compose ----------
$L = New-Object System.Collections.Generic.List[string]
$L.Add('# Engram scorecard')
$L.Add('<!-- GENERATED by engram-scorecard from metrics/events.jsonl -- do not hand-edit. -->')
$L.Add('')
$L.Add('## Retrieval')
$L.Add('')
if ($recalls.Count -eq 0) {
    $L.Add('*No recall events yet -- /mem-recall logs one event per memory-served question; this table populates once recalls happen.*')
    $L.Add('')
}
$L.Add('| Window | Recalls | Hit | Verified | Miss | Hit rate | Backfill rate | Mean files read |')
$L.Add('|--------|---------|-----|----------|------|----------|---------------|-----------------|')
$L.Add((RetrievalRow 'all-time' $recalls))
$L.Add((RetrievalRow 'last 30d' $recent))
$L.Add('')

$models = @($recalls | ForEach-Object { $_.model } | Where-Object { $_ } | Select-Object -Unique)
[Array]::Sort($models, [System.StringComparer]::Ordinal)
if ($models.Count -gt 1) {
    $L.Add('## Per-model')
    $L.Add('')
    $L.Add('| Model | Recalls | Hit rate | Mean files_read | Mean mem_files_read |')
    $L.Add('|-------|---------|----------|-----------------|---------------------|')
    foreach ($mo in $models) {
        $sub = @($recalls | Where-Object { $_.model -eq $mo })
        $n = $sub.Count
        $ok = 0
        foreach ($e in $sub) { if ($e.outcome -eq 'hit' -or $e.outcome -eq 'verified') { $ok++ } }
        $hr = Pct $ok $n
        $mf = '--'; $m = MeanKey $sub 'files_read';     if ($null -ne $m) { $mf = Fmt1 $m }
        $mm = '--'; $m = MeanKey $sub 'mem_files_read'; if ($null -ne $m) { $mm = Fmt1 $m }
        $L.Add("| $mo | $n | $hr | $mf | $mm |")
    }
    $L.Add('')
}

# cost ledger
$marg = 'no recall data'
$imr  = '--'
$ben  = 'no recall data'
if ($recalls.Count -gt 0) {
    $mmf = MeanKey $recalls 'mem_files_read'
    $mgl = MeanKey $recalls 'mem_grep_lines'
    $a = 'n/a'; if ($null -ne $mmf) { $a = Fmt1 $mmf }
    $b = 'n/a'; $tok = ''
    if ($null -ne $mgl) { $b = Fmt1 $mgl; $tok = " (~$(FloorX ($mgl * 10 + 0.5)) tok)" }
    if (($null -eq $mmf) -and ($null -eq $mgl)) { $marg = 'n/a (no field data)' }
    else { $marg = "$a mem files + $b grep lines$tok per recall" }

    $den = 0; $num = 0
    foreach ($e in $recalls) {
        if ((HasKey $e 'mem_greps') -and ($null -ne $e.mem_greps)) {
            $den++
            if ([double]$e.mem_greps -gt 0) { $num++ }
        }
    }
    if ($den -gt 0) { $imr = Pct $num $den }

    $hitsub  = @($recalls | Where-Object { $_.outcome -eq 'hit' -or $_.outcome -eq 'verified' })
    $misssub = @($recalls | Where-Object { $_.outcome -eq 'miss' })
    $mh = MeanKey $hitsub 'files_read'
    $mm2 = MeanKey $misssub 'files_read'
    if (($null -ne $mh) -and ($null -ne $mm2)) {
        $ben = "mean files_read miss $(Fmt1 $mm2) vs hit $(Fmt1 $mh) -> ~$(Fmt1 ($mm2 - $mh)) saved per hit x $($hitsub.Count) hits"
    } else {
        $ben = '-- (need both hits and misses)'
    }
}
$L.Add("**Cost ledger:** fixed overhead $idxLines index lines (always loaded); marginal overhead $marg; index-miss rate $imr; benefit $ben.")

$dead = 0
foreach ($e in $recalls) { if ((HasKey $e 'dead_end_cited') -and ($e.dead_end_cited -eq $true)) { $dead++ } }
# exact repeat misses over normalized questions, listed in order of second occurrence
$seen = @{}
$dups = New-Object System.Collections.Generic.List[string]
foreach ($e in $recalls) {
    if ($e.outcome -ne 'miss') { continue }
    $q = ''
    if ((HasKey $e 'q') -and ($null -ne $e.q)) { $q = [string]$e.q }
    $nq = ([regex]::Replace($q.ToLowerInvariant(), '[^a-z0-9]+', ' ')).Trim()
    if (-not $nq) { continue }
    if ($seen.ContainsKey($nq)) {
        if (-not $dups.Contains($nq)) { $dups.Add($nq) }
    } else { $seen[$nq] = 1 }
}
$rm = 'none'
if ($dups.Count -gt 0) { $rm = ($dups -join '; ') }
$L.Add("**Dead-end saves:** $dead cited. **Repeat misses (exact):** $rm -- semantic near-duplicates are judged by /mem-sync.")
$L.Add('')

$L.Add('## Health trend (sync snapshots)')
$L.Add('')
if ($syncs.Count -eq 0) {
    $L.Add('*No sync snapshots yet -- /mem-sync appends one per run.*')
} else {
    $L.Add('| Date | HEAD | Cards | Fresh | Mean behind | Index lines | Entries 14d |')
    $L.Add('|------|------|-------|-------|-------------|-------------|-------------|')
    $start = 0
    if ($syncs.Count -gt 6) { $start = $syncs.Count - 6 }
    for ($i = $start; $i -lt $syncs.Count; $i++) {
        $s = $syncs[$i]
        $mb = '--'
        if ((HasKey $s 'mean_behind') -and ($null -ne $s.mean_behind)) { $mb = Fmt1 ([double]$s.mean_behind) }
        $cards = 0; if ((HasKey $s 'cards') -and ($null -ne $s.cards)) { $cards = $s.cards }
        $fresh = 0; if ((HasKey $s 'fresh') -and ($null -ne $s.fresh)) { $fresh = $s.fresh }
        $il = 0;    if ((HasKey $s 'index_lines') -and ($null -ne $s.index_lines)) { $il = $s.index_lines }
        $e14 = 0;   if ((HasKey $s 'journal_entries_14d') -and ($null -ne $s.journal_entries_14d)) { $e14 = $s.journal_entries_14d }
        $L.Add("| $($s.ts) | $($s.head) | $cards | $fresh | $mb | $il | $e14 |")
    }
}

$text = ($L -join "`n") + "`n"
$null = New-Item -ItemType Directory -Force -Path "$memdir/metrics"
[System.IO.File]::WriteAllText($outPath, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "engram-scorecard: $($recalls.Count) recalls, $($syncs.Count) syncs -> .claude/memory/metrics/scorecard.md"
exit 0
