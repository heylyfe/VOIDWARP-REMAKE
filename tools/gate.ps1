# tools/gate.ps1 - the merge gate (FLEET_PACK.md section 4).
#
#   powershell -File tools\gate.ps1
#
# Runs the steps below IN ORDER and stops at the first failure. Exit code 0 = green, 1 = red.
# A step whose input file does not exist yet prints "SKIP <step> (pending T-XXX)" and counts as
# neither pass nor fail. Formatting is never a gate step. The 5,000-seed harness and the export are
# deliberately NOT here (tools\harness.ps1 and T-056).
#
#   1 python oracle checks   terrain_ref\test_validate.py, validate.py --selftest, gallery.py --check
#   2 terrain parity         game/tests/test_terrain_parity.gd      (GDScript vs Python goldens)
#   3 run_all                game/tests/run_all.gd                  (pending T-001)
#   4 boundary scan          game/tests/test_boundaries.gd          (pending T-001)
#   5 content schema         game/tests/test_content.gd             (pending T-013)
#   6 drop-in fixture        game/tests/test_dropin.gd              (pending T-013)
#   7 replay determinism     game/tests/test_replay.gd              (pending T-010)
#   8 sprite validator       game/tools/validate_sprites.gd         (pending T-016)
#   9 fog readability        game/tools/fog_check.gd                (pending T-011)
#
# Steps 4-7 are test_*.gd files that run_all.gd discovers and runs, so they are executed by step 3.
# The gate reports each one separately: OK when the file exists and step 3 was green, SKIP when the
# file is not there yet. A failure in any of them is a failure of step 3 and stops the gate there.
#
# A step is green only if the process exits 0 AND prints its expected result line. Godot can exit 0
# after a script fails to load, so the exit code alone is never trusted.
#
# Godot is looked up in this order: $env:GODOT, <this checkout>\tools\godot\godot.exe, then the main
# checkout's tools\godot\godot.exe. The last one matters in a git worktree: the engine binary is
# gitignored, so a worktree has no copy of its own.
#
# Works in Windows PowerShell 5.1. Keep this file ASCII-only (5.1 reads a BOM-less file as ANSI).

param(
    [int]$StepTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$GateStart = Get-Date
$Results = New-Object System.Collections.ArrayList

function Add-Result([string]$Status, [string]$Step, [string]$Note) {
    [void]$Results.Add([pscustomobject]@{ Status = $Status; Step = $Step; Note = $Note })
}

function Write-Summary {
    Write-Host ''
    Write-Host '---- gate summary ----'
    foreach ($r in $Results) {
        if ($r.Note) { Write-Host ("{0,-4} {1} ({2})" -f $r.Status, $r.Step, $r.Note) }
        else { Write-Host ("{0,-4} {1}" -f $r.Status, $r.Step) }
    }
}

function Stop-Gate([string]$Step, [string]$Reason) {
    Add-Result 'FAIL' $Step $Reason
    Write-Host "FAIL $Step ($Reason)"
    Write-Summary
    $secs = [int]((Get-Date) - $GateStart).TotalSeconds
    Write-Host "GATE FAIL at: $Step ($secs s)"
    exit 1
}

function Skip-Step([string]$Step, [string]$Ticket) {
    Add-Result 'SKIP' $Step "pending $Ticket"
    Write-Host "SKIP $Step (pending $Ticket)"
}

function Pass-Step([string]$Step, [string]$Note) {
    Add-Result 'OK' $Step $Note
    if ($Note) { Write-Host "OK $Step ($Note)" } else { Write-Host "OK $Step" }
}

# Runs one process from the repo root, prints its output, returns exit code + captured text.
# Start-Process / the call operator are avoided on purpose: in PowerShell 5.1 a native program that
# writes to stderr turns into an error record, and paths with spaces need explicit quoting.
function Invoke-Tool([string]$Exe, [string[]]$Arguments) {
    $quoted = foreach ($a in $Arguments) {
        if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($quoted -join ' ')
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'

    Write-Host ("  > {0} {1}" -f (Split-Path -Leaf $Exe), $psi.Arguments)
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $timedOut = -not $p.WaitForExit($StepTimeoutSec * 1000)
    if ($timedOut) {
        try { $p.Kill() } catch { }
        $p.WaitForExit()
    } else {
        $p.WaitForExit()   # flushes the async readers
    }
    $text = $outTask.Result
    if ($errTask.Result) { $text = $text + "`n" + $errTask.Result }
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.Trim()) { Write-Host "    $line" }
    }
    $code = $p.ExitCode
    $p.Dispose()
    return [pscustomobject]@{ Code = $code; Text = $text; TimedOut = $timedOut }
}

# Fails the gate unless the run exited 0 in time. Returns the captured text.
function Assert-Run([string]$Step, $Run) {
    if ($Run.TimedOut) { Stop-Gate $Step "timed out after $StepTimeoutSec s" }
    if ($Run.Code -ne 0) { Stop-Gate $Step "exit code $($Run.Code)" }
    return $Run.Text
}

# A Godot --script run that failed to load can still exit 0. Catch that.
function Assert-NoScriptError([string]$Step, [string]$Text) {
    if ($Text -match '(?m)^\s*(SCRIPT ERROR|Parse Error|ERROR: Failed to load script|ERROR: Can''t load script)') {
        Stop-Gate $Step 'Godot reported a script error'
    }
}

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

function Find-Python {
    if ($env:PYTHON) { return $env:PYTHON }
    foreach ($name in @('python', 'py')) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Test-Input([string]$RelPath) {
    return (Test-Path -LiteralPath (Join-Path $Root $RelPath) -PathType Leaf)
}

Write-Host "GATE $Root"

# ---- 1. python oracle checks -------------------------------------------------------------------
$step = 'python oracle checks'
Write-Host "STEP 1 $step"
$Python = Find-Python
if (-not $Python) { Stop-Gate $step 'python not found on PATH (set $env:PYTHON)' }

$t = Assert-Run $step (Invoke-Tool $Python @('terrain_ref\test_validate.py'))
if ($t -notmatch '(?m)^\s*TESTS OK\s*$') { Stop-Gate $step 'test_validate.py did not print TESTS OK' }

$t = Assert-Run $step (Invoke-Tool $Python @('terrain_ref\validate.py', '--selftest'))
$m = [regex]::Matches($t, 'SELFTEST (\d+)/(\d+)')
if ($m.Count -eq 0) { Stop-Gate $step 'validate.py --selftest did not print SELFTEST n/n' }
$last = $m[$m.Count - 1]
if ($last.Groups[1].Value -ne $last.Groups[2].Value) { Stop-Gate $step "selftest $($last.Value): a planted defect was not caught" }
$selftest = $last.Value

$t = Assert-Run $step (Invoke-Tool $Python @('terrain_ref\gallery.py', '--check'))
$m = [regex]::Match($t, 'GALLERY (\d+)/(\d+) OK')
if (-not $m.Success -or $m.Groups[1].Value -ne $m.Groups[2].Value) { Stop-Gate $step 'gallery.py --check did not print GALLERY n/n OK' }
Pass-Step $step "TESTS OK, $selftest, $($m.Value)"

# ---- 2. terrain parity -------------------------------------------------------------------------
$step = 'terrain parity'
Write-Host "STEP 2 $step"
$Godot = Find-Godot
if (-not $Godot) { Stop-Gate $step 'godot.exe not found (see tools\godot\README.md, or set $env:GODOT)' }
$GodotBase = @('--headless', '--path', (Join-Path $Root 'game'), '--script')

$t = Assert-Run $step (Invoke-Tool $Godot ($GodotBase + @('res://tests/test_terrain_parity.gd', '--', (Join-Path $Root 'terrain_ref\gallery.json'))))
$m = [regex]::Match($t, '(?m)^\s*PARITY (\d+)/(\d+) OK\s*$')
if (-not $m.Success -or $m.Groups[1].Value -ne $m.Groups[2].Value -or $m.Groups[2].Value -eq '0') { Stop-Gate $step 'did not print PARITY n/n OK' }
Pass-Step $step $m.Value.Trim()

# ---- 3. run_all.gd -----------------------------------------------------------------------------
$step = 'run_all'
Write-Host "STEP 3 $step"
$ranAll = $false
if (Test-Input 'game\tests\run_all.gd') {
    $t = Assert-Run $step (Invoke-Tool $Godot ($GodotBase + @('res://tests/run_all.gd')))
    Assert-NoScriptError $step $t
    $m = [regex]::Matches($t, 'TESTS (\d+) passed (\d+) failed')
    if ($m.Count -eq 0) { Stop-Gate $step 'did not print TESTS n passed m failed' }
    $last = $m[$m.Count - 1]
    if ($last.Groups[2].Value -ne '0') { Stop-Gate $step $last.Value }
    Pass-Step $step $last.Value
    $ranAll = $true
} else {
    Skip-Step $step 'T-001'
}

# ---- 4-7. tests that run_all.gd executes -------------------------------------------------------
$covered = @(
    @{ N = 4; Step = 'boundary scan';      File = 'game\tests\test_boundaries.gd'; Ticket = 'T-001' },
    @{ N = 5; Step = 'content schema';     File = 'game\tests\test_content.gd';    Ticket = 'T-013' },
    @{ N = 6; Step = 'drop-in fixture';    File = 'game\tests\test_dropin.gd';     Ticket = 'T-013' },
    @{ N = 7; Step = 'replay determinism'; File = 'game\tests\test_replay.gd';     Ticket = 'T-010' }
)
foreach ($c in $covered) {
    Write-Host "STEP $($c.N) $($c.Step)"
    if (-not (Test-Input $c.File)) { Skip-Step $c.Step $c.Ticket }
    elseif (-not $ranAll) { Skip-Step $c.Step 'T-001' }   # the file exists but the runner does not
    else { Pass-Step $c.Step ("ran in run_all: " + ($c.File -replace '\\', '/')) }
}

# ---- 8-9. standalone headless tools ------------------------------------------------------------
$tools = @(
    @{ N = 8; Step = 'sprite validator'; File = 'game\tools\validate_sprites.gd'; Res = 'res://tools/validate_sprites.gd'; Ticket = 'T-016' },
    @{ N = 9; Step = 'fog readability';  File = 'game\tools\fog_check.gd';        Res = 'res://tools/fog_check.gd';        Ticket = 'T-011' }
)
foreach ($c in $tools) {
    Write-Host "STEP $($c.N) $($c.Step)"
    if (-not (Test-Input $c.File)) { Skip-Step $c.Step $c.Ticket; continue }
    $t = Assert-Run $c.Step (Invoke-Tool $Godot ($GodotBase + @($c.Res)))
    Assert-NoScriptError $c.Step $t
    Pass-Step $c.Step ''
}

# ---- done --------------------------------------------------------------------------------------
Write-Summary
$ran = @($Results | Where-Object { $_.Status -eq 'OK' }).Count
$skipped = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count
$secs = [int]((Get-Date) - $GateStart).TotalSeconds
Write-Host "GATE OK ($ran ran, $skipped skipped, $secs s)"
exit 0
