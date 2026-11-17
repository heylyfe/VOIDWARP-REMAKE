# tools/run_batch.ps1 - the T-081 batch: N logged bot runs, then the fun-risk report.
#
#   powershell -NoProfile -File tools\run_batch.ps1              (100 runs, seeds 0-99)
#   powershell -NoProfile -File tools\run_batch.ps1 -Runs 20 -SeedBase 60717
#
# Runs bot_run.gd with logging on (--dodge, T-060's vote rules; one T-080 run log per
# seed under out\run_logs, gitignored), then run_report.gd over the folder. The report
# is INFORMATION: no pass/fail, no threshold - it prints and is tee'd to
# out\run_report.txt. The write goes only where the logs land; nothing else is touched.

param(
    [int]$Runs = 100,
    [int]$SeedBase = 0
)
$ErrorActionPreference = 'Stop'
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
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

$LogDir = Join-Path $Root 'out\run_logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Godot = Find-Godot
if (-not $Godot) {
    Write-Host 'BATCH FAIL: godot.exe not found (see tools\godot\README.md, or set $env:GODOT)'
    exit 1
}

Write-Host "BATCH: $Runs runs, seeds $SeedBase..$($SeedBase + $Runs - 1), logs in $LogDir"
& $Godot --headless --path (Join-Path $Root 'game') --script res://tools/bot_run.gd -- `
    --dodge --runs $Runs --seed-base $SeedBase --log --log-dir $LogDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "BATCH FAIL: bot_run exited $LASTEXITCODE"
    exit 1
}

$ReportPath = Join-Path $Root 'out\run_report.txt'
& $Godot --headless --path (Join-Path $Root 'game') --script res://tools/run_report.gd -- $LogDir |
    Tee-Object -FilePath $ReportPath
Write-Host "BATCH OK: report at $ReportPath"
exit 0
