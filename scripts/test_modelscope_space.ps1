[CmdletBinding()]
param(
    [string]$SpaceDirectory = "artifacts/modelscope-studio"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$spaceRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $SpaceDirectory))

if (-not (Test-Path -LiteralPath (Join-Path $spaceRoot "app.py"))) {
    & (Join-Path $PSScriptRoot "build_modelscope_space.ps1") -OutputDirectory $SpaceDirectory
}

python -m compileall -q $spaceRoot
if ($LASTEXITCODE -ne 0) { throw "Python compile check failed" }

Get-ChildItem -LiteralPath $spaceRoot -Directory -Filter "__pycache__" -Recurse | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}

python -m pytest (Join-Path $repositoryRoot "deploy/modelscope/tests") -q
if ($LASTEXITCODE -ne 0) { throw "Studio contract tests failed" }

Write-Output "ModelScope Studio static checks passed."
