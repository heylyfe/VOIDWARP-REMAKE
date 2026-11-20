# tools/build_models.ps1 - T-015: rebuild all 12 procedural models in one command.
#
#   powershell -File tools\build_models.ps1
#
# Runs every assets_src\blender\*.py headless (the scripts are the source of
# truth) and writes game\assets\models\<name>.glb (build artifacts). Deterministic:
# two runs produce byte-identical .glb files.
#
# Blender discovery order (FLEET_PACK R19: the portable install lives only in the
# main checkout, so a worktree falls through to the absolute path):
#   1. $env:BLENDER
#   2. tools\blender\blender.exe in this checkout
#   3. the main-checkout absolute path

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$MainBlender = "$env:USERPROFILE\Documents\REMAKE VWR\VOIDWARP-REMAKE\tools\blender\blender.exe"

function Resolve-Blender {
    foreach ($cand in @($env:BLENDER,
                       (Join-Path $PSScriptRoot 'blender\blender.exe'),
                       $MainBlender)) {
        if ($cand -and (Test-Path $cand)) { return (Resolve-Path $cand).Path }
    }
    throw 'Blender not found: set $env:BLENDER or install tools\blender\blender.exe'
}

$Blender = Resolve-Blender
Write-Host ("BLENDER " + $Blender)

$ScriptDir = Join-Path $Root 'assets_src\blender'
$OutDir = Join-Path $Root 'game\assets\models'
$Scripts = Get-ChildItem -Path $ScriptDir -Filter '*.py' |
    Where-Object { $_.Name -ne 't015_common.py' } |
    Sort-Object Name
if ($Scripts.Count -ne 12) {
    throw ("expected 12 model scripts in assets_src\blender, found " + $Scripts.Count)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$env:T015_MODELS_OUT = $OutDir

$i = 0
foreach ($s in $Scripts) {
    $i++
    Write-Host ("[{0}/12] {1}" -f $i, $s.Name)
    $out = & $Blender --background --python $s.FullName --python-exit-code 1 2>&1
    if ($LASTEXITCODE -ne 0) {
        $out | ForEach-Object { Write-Host $_ }
        throw ("blender failed on " + $s.Name)
    }
    $line = ($out | Where-Object { $_ -match '^T015_WROTE ' } | Select-Object -Last 1)
    if (-not $line) { throw ($s.Name + " did not report T015_WROTE") }
    Write-Host $line
}

Remove-Item Env:T015_MODELS_OUT -ErrorAction SilentlyContinue
Write-Host 'BUILD OK (12/12 models)'