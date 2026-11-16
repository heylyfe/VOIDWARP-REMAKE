# tools/harness.ps1 - the full generation harness (FLEET_PACK.md section 4).
# Runs the 5,000-seed validator and exits with its exit code.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
python terrain_ref\validate.py --seeds 0:5000
exit $LASTEXITCODE
