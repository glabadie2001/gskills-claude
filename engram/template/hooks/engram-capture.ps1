# engram-capture.ps1 -- Engram auto-capture hook (PreCompact + SessionEnd).
#
# Drafts a journal entry from the session transcript via headless Claude, then
# appends it to today's journal file. This is a best-effort SIDE EFFECT: every
# failure mode degrades silently and the script ALWAYS exits 0, so it can never
# break a session.
#
# Windows PowerShell 5.1 compatible (no ??, no ternary, no -AsHashtable).
# NOTE: source is kept pure ASCII so PS 5.1 reads it correctly without a BOM;
# the em dash / middle dot that Engram journals use are built from char codes.

# Model for the headless draft. Default: fast + cheap.
# Bump to a sonnet model (e.g. claude-sonnet-4-6) for richer drafts.
$MODEL = 'claude-haiku-4-5'

$ErrorActionPreference = 'SilentlyContinue'

try {
    # ---------- re-entry guard (belt on top of --bare) ----------
    # Checked BEFORE we set it for the child spawn below.
    if ($env:ENGRAM_CAPTURE -eq '1') { exit 0 }

    # ---------- read stdin JSON ----------
    $eventName = ''
    $transcriptPath = ''
    $cwdVal = ''
    $reason = ''
    try {
        $raw = [Console]::In.ReadToEnd()
        if ($raw -and $raw.Trim().Length -gt 0) {
            $payload = $raw | ConvertFrom-Json
            if ($payload) {
                if ($payload.PSObject.Properties['hook_event_name']) { $eventName      = [string]$payload.hook_event_name }
                if ($payload.PSObject.Properties['transcript_path'])  { $transcriptPath = [string]$payload.transcript_path }
                if ($payload.PSObject.Properties['cwd'])              { $cwdVal         = [string]$payload.cwd }
                if ($payload.PSObject.Properties['reason'])           { $reason         = [string]$payload.reason }
            }
        }
    } catch { exit 0 }

    # ---------- resolve project root ----------
    $root = $env:CLAUDE_PROJECT_DIR
    if (-not $root) { $root = $cwdVal }
    if (-not $root) { $root = (Get-Location).Path }

    # ---------- guard: memory present and initialized ----------
    $memDir   = Join-Path $root '.claude\memory'
    $memoryMd = Join-Path $memDir 'MEMORY.md'
    if (-not (Test-Path -LiteralPath $memoryMd)) { exit 0 }
    $memoryText = ''
    try { $memoryText = [System.IO.File]::ReadAllText($memoryMd) } catch { exit 0 }
    if ($memoryText.IndexOf('STATUS: EMPTY') -ge 0) { exit 0 }

    # ---------- guard: transcript readable ----------
    if (-not $transcriptPath) { exit 0 }
    if (-not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) { exit 0 }

    $today = Get-Date -Format 'yyyy-MM-dd'

    # ---------- SessionEnd-only guards ----------
    # PreCompact implies a substantial session, so it has no heuristic.
    if ($eventName -eq 'SessionEnd') {
        # Session continues later -> skip.
        if ($reason -eq 'resume') { exit 0 }

        # Heuristic 1: trivial session (transcript under 80 KB).
        $size = 0
        try { $size = (Get-Item -LiteralPath $transcriptPath).Length } catch { $size = 0 }
        if ($size -lt 81920) { exit 0 }

        # Heuristic 2: today's journal already has an entry within the last 2 hours.
        $todayJournal = Join-Path (Join-Path $memDir 'journal') ($today + '.md')
        if (Test-Path -LiteralPath $todayJournal) {
            $lastHH = -1; $lastMM = -1
            try {
                $jl = [System.IO.File]::ReadAllLines($todayJournal)
                foreach ($line in $jl) {
                    $m = [regex]::Match($line, '^##\s+(\d\d):(\d\d)\b')
                    if ($m.Success) {
                        $lastHH = [int]$m.Groups[1].Value
                        $lastMM = [int]$m.Groups[2].Value
                    }
                }
            } catch { }
            if ($lastHH -ge 0) {
                $entryTime = $null
                try { $entryTime = Get-Date -Hour $lastHH -Minute $lastMM -Second 0 } catch { $entryTime = $null }
                if ($entryTime) {
                    $diffMin = ((Get-Date) - $entryTime).TotalMinutes
                    if ($diffMin -ge 0 -and $diffMin -lt 120) { exit 0 }
                }
            }
        }
    }

    # ---------- compose the extraction prompt ----------
    $nowHM  = Get-Date -Format 'HH:mm'
    $emDash = [string][char]0x2014
    $midDot = [string][char]0x00B7

    $promptTemplate = @'
Read the Claude Code session transcript (JSONL) at this path:
<<PATH>>
The file may be large. Read the tail portions that cover the actual work done in the session.

Decide whether anything DURABLE happened in this session: completed tasks, fixed bugs,
non-obvious learnings, dead ends, or decisions worth remembering later. If the session
was routine question-and-answer, exploration with no concrete outcome, or otherwise
trivial, output exactly this single word and nothing else:
SKIP

Otherwise output ONLY a journal entry in EXACTLY this format. No preamble, no code
fences, no trailing commentary -- only the entry:

## <<TIME>> <<EMDASH>> One-line headline of what happened [<your exact model id> <<MIDDOT>> auto-draft]
- **Did:** what was accomplished, concretely -- wikilink the primary module(s) once, e.g. [[module-name]]
- **Learned:** non-obvious facts discovered (omit this whole line if none)
- **Dead ends:** what was tried and FAILED and why; mark each dead: or parked: (omit if none)
- **Touched:** files changed
- **Commits:** short commit shas this work produced (omit if none -- never invent a sha)
- **Next:** follow-ups worth filing (omit if none)
- **Note:** auto-captured from transcript (unreviewed) <<EMDASH>> verify before trusting

Hard rules:
- The headline time MUST be exactly <<TIME>> and the signature MUST end with <<MIDDOT>> auto-draft].
- Sign the headline with your own exact model id.
- Keep the entry to 12 lines or fewer. Omit every field that has no content.
- Today's date is <<DATE>>.
- Output the journal entry, or the single word SKIP. Nothing else.
'@

    $prompt = $promptTemplate.Replace('<<PATH>>', $transcriptPath).Replace('<<TIME>>', $nowHM).Replace('<<DATE>>', $today).Replace('<<EMDASH>>', $emDash).Replace('<<MIDDOT>>', $midDot)

    # ---------- spawn headless Claude ----------
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) { exit 0 }

    $env:ENGRAM_CAPTURE = '1'
    $raw2 = $null
    try {
        $raw2 = & claude --bare -p $prompt --allowedTools 'Read' --model $MODEL 2>$null
    } catch { exit 0 }
    if ($LASTEXITCODE -ne 0) { exit 0 }

    $output = ($raw2 | Out-String)
    if (-not $output) { exit 0 }
    $output = $output.Replace("`r`n", "`n").Replace("`r", "`n").Trim()
    if (-not $output) { exit 0 }

    # ---------- validate ----------
    if (-not $output.StartsWith('## ')) { exit 0 }
    $firstLine = ($output -split "`n", 2)[0]
    # Lenient on the dash: accept a hyphen or the em dash.
    $pattern = '^## \d\d:\d\d (' + $emDash + '|-) .+\[.+auto-draft\]'
    if ($firstLine -notmatch $pattern) { exit 0 }

    # ---------- append to today's journal (never overwrite) ----------
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $journalDir = Join-Path $memDir 'journal'
    if (-not (Test-Path -LiteralPath $journalDir)) {
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
    }
    $journalFile = Join-Path $journalDir ($today + '.md')

    if (-not (Test-Path -LiteralPath $journalFile)) {
        $header  = '# Journal ' + $emDash + ' ' + $today
        $content = $header + "`n`n" + $output + "`n"
        [System.IO.File]::WriteAllText($journalFile, $content, $utf8NoBom)
    } else {
        $existing = ''
        try { $existing = [System.IO.File]::ReadAllText($journalFile) } catch { $existing = '' }
        # Preserve all existing content; normalize only the trailing whitespace so
        # there is exactly one blank line before the new entry.
        $existing = $existing.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd()
        $content = $existing + "`n`n" + $output + "`n"
        [System.IO.File]::WriteAllText($journalFile, $content, $utf8NoBom)
    }

    exit 0
} catch {
    exit 0
}
