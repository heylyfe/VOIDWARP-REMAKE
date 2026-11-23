# tools/build_tester.ps1 - the owner-only TESTER build (cycle 7, track T2).
#
#   powershell -File tools\build_tester.ps1
#
# Exports the "Tester" preset (export_presets.cfg preset.3, custom_features="tester")
# to game\out\tester\voidwrap_tester.exe. That preset packs the debug panel
# (res://view/tester/), which the three public presets exclude, so the panel exists ONLY
# in this exe. The output folder is gitignored (out/), the exe is NEVER uploaded, it is
# NEVER attached to a release, and .github/workflows/build.yml names the three public
# presets by hand - it cannot pick this one up.
#
# The engine is looked up exactly like tools\gate.ps1: $env:GODOT, this checkout's
# tools\godot\godot.exe (absent in a git worktree, it is gitignored), then the main
# checkout's. Works in Windows PowerShell 5.1. Keep this file ASCII-only.
#
# Exits 0 only when the exe exists and is > 1 MB (the same "that is a build" floor CI uses).

param(
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$GameDir = Join-Path $Root 'game'
$OutExe = Join-Path $Root 'game\out\tester\voidwrap_tester.exe'

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

$Godot = Find-Godot
if (-not $Godot) {
    Write-Host 'TESTER BUILD FAIL: godot.exe not found (set $env:GODOT, or see tools\godot\README.md)'
    exit 1
}

# A fresh worktree has no game\.godot: import once so the export has resources to pack.
Write-Host 'TESTER: resource import'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Godot
$psi.Arguments = '--headless --path "' + $GameDir + '" --import'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $false
$p = [System.Diagnostics.Process]::Start($psi)
if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch { } }
Write-Host ("TESTER: import exit {0}" -f $p.ExitCode)

# Godot resolves the export/output paths against the project dir (game\), so an absolute
# native path is passed explicitly and the out dir is created first.
$outDir = Split-Path -Parent $OutExe
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Write-Host 'TESTER: exporting preset "Tester" (custom_features="tester")'
$psi2 = New-Object System.Diagnostics.ProcessStartInfo
$psi2.FileName = $Godot
$psi2.Arguments = '--headless --path "' + $GameDir + '" --export-release "Tester" "' + $OutExe + '"'
$psi2.UseShellExecute = $false
$psi2.CreateNoWindow = $true
$psi2.RedirectStandardOutput = $true
$psi2.RedirectStandardError = $true
$q = [System.Diagnostics.Process]::Start($psi2)
$outTask = $q.StandardOutput.ReadToEndAsync()
$errTask = $q.StandardError.ReadToEndAsync()
$timedOut = -not $q.WaitForExit($TimeoutSec * 1000)
if ($timedOut) { try { $q.Kill() } catch { } }
$q.WaitForExit()
$text = $outTask.Result
if ($errTask.Result) { $text = $text + "`n" + $errTask.Result }
foreach ($line in ($text -split "`r?`n")) {
    if ($line.Trim()) { Write-Host "    $line" }
}
if ($q.ExitCode -ne 0) {
    Write-Host "TESTER BUILD FAIL: export exited with code $($q.ExitCode)"
    exit 1
}

if (-not (Test-Path -LiteralPath $OutExe -PathType Leaf)) {
    Write-Host "TESTER BUILD FAIL: export produced no file at $OutExe"
    exit 1
}
$bytes = (Get-Item -LiteralPath $OutExe).Length
if ($bytes -lt 1000000) {
    Write-Host "TESTER BUILD FAIL: export is only $bytes bytes; that is not a build"
    exit 1
}
Write-Host ("TESTER BUILD OK: {0} ({1:N0} bytes)" -f $OutExe, $bytes)
Write-Host 'TESTER: this exe is owner-only - never uploaded, never in a release.'
exit 0
