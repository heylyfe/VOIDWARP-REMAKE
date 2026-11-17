# tools/run_batch.ps1 - the T-081 batch: N logged bot runs, then the fun-risk report.
#
#   powershell -NoProfile -File tools\run_batch.ps1              (100 runs, seeds 0-99)
#   powershell -NoProfile -File tools\run_batch.ps1 -Runs 40 -SeedBase 100
#
# Runs bot_run.gd with logging on (--dodge, T-060's seeded-random votes; one T-080 run
# log per seed under out\run_logs, gitignored) in CHUNKS of 25 seeds per godot process
# - one long 100-run process died at ~63 runs in this session (no error printed, exit
# nonzero; single seeds replay clean, so it is accumulated state in the long-running
# process, not a seed) - then run_report.gd over the folder. The report is
# INFORMATION: no pass/fail, no threshold; it prints and is tee'd to
# out\run_report.txt. A chunk that exits nonzero is reported and skipped, not fatal:
# the report states the runs it actually found.

param(
    [int]$Runs = 100,
    [int]$SeedBase = 0,
    [int]$Chunk = 25
)
$ErrorHeader = 'BATCH FAIL'
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot

function Find-Godot {
    $candidates = New-Object System.Collections.ArrayList
    if ($env:GODOT) { [void]$candidates.Add($env:GODOT) }
    [void]$candidates.Add((Join-Path $Root 'tools\godot\godot.exe'))
    try {
        $common = (& git -C $Root rev-parse --path-format=absolute --git-common-dir 2>$null)
        if ($LASTEXITCODE -eq 0 -and $common) {
            $mainRoot = Split-Path -Parent ([string]$common).Trim().Replace('/', '\')
            [void]$candidates.Add((Join-Path $mainRoot 'tools\godot\godot.exe'))
        }
    } catch { }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$LogDir = Join-Path $Root 'out\run_logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Godot = Find-Godot
if (-not $Godot) {
    Write-Host "$ErrorHeader : godot.exe not found (see tools\godot\README.md, or set `$env:GODOT)"
    exit 1
}

$Done = 0
$FailedChunks = 0
while ($Done -lt $Runs) {
    $n = [Math]::Min($Chunk, $Runs - $Done)
    $base = $SeedBase + $Done
    Write-Host "BATCH: seeds $base..$($base + $n - 1) (log dir $LogDir)"
    & $Godot --headless --path (Join-Path $Root 'game') --script res://tools/bot_run.gd -- --dodge --runs $n --seed-base $base --log --log-dir $LogDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BATCH WARNING: bot_run exited $LASTEXITCODE for seeds $base..$($base + $n - 1); continuing"
        $FailedChunks += 1
    }
    $Done += $n
}

$ReportPath = Join-Path $Root 'out\run_report.txt'
& $Godot --headless --path (Join-Path $Root 'game') --script res://tools/run_report.gd -- $LogDir | Tee-Object -FilePath $ReportPath
if ($FailedChunks -gt 0) {
    Write-Host "BATCH DONE WITH $FailedChunks FAILED CHUNK(S): the report above covers the logs that exist"
    exit 2
}
Write-Host "BATCH OK: $Runs runs requested, report at $ReportPath"
exit 0
