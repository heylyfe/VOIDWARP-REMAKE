# T-015 helper: SHA-256 of every model .glb, sorted, one per line.
$Root = Split-Path -Parent $PSScriptRoot
Get-ChildItem (Join-Path $Root 'game\assets\models') -Filter '*.glb' |
    Sort-Object Name |
    ForEach-Object {
        $h = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLower()
        Write-Output ("{0}  {1}" -f $h, $_.Name)
    }
