[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryUrl,
    [string]$SpaceDirectory = "artifacts/modelscope-studio"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$spaceRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $SpaceDirectory))
$envPath = Join-Path $repositoryRoot ".env"

if (-not (Test-Path -LiteralPath $envPath)) { throw "Missing local .env" }
$tokenLine = Get-Content -LiteralPath $envPath | Where-Object { $_ -match '^MODELSCOPE_API_TOKEN=' } | Select-Object -Last 1
if (-not $tokenLine) { throw "MODELSCOPE_API_TOKEN is not configured in .env" }
$token = ($tokenLine -split '=', 2)[1].Trim()
if (-not $token) { throw "MODELSCOPE_API_TOKEN is empty" }

& (Join-Path $PSScriptRoot "build_modelscope_space.ps1") -OutputDirectory $SpaceDirectory
& (Join-Path $PSScriptRoot "test_modelscope_space.ps1") -SpaceDirectory $SpaceDirectory

$publishRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nature-sound-detective-modelscope-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $publishRoot | Out-Null
try {
    $uri = [Uri]$RepositoryUrl
    $authenticated = "{0}://oauth2:{1}@{2}{3}" -f $uri.Scheme, [Uri]::EscapeDataString($token), $uri.Authority, $uri.PathAndQuery
    git clone $authenticated $publishRoot
    if ($LASTEXITCODE -ne 0) { throw "Unable to clone ModelScope Studio repository" }

    Get-ChildItem -LiteralPath $publishRoot -Force | Where-Object { $_.Name -ne ".git" } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    Copy-Item -Path (Join-Path $spaceRoot "*") -Destination $publishRoot -Recurse -Force
    git -C $publishRoot add --all
    git -C $publishRoot -c user.name="gqy20" -c user.email="actions@users.noreply.github.com" commit -m "Deploy nature-sound-detective 0.1.0"
    if ($LASTEXITCODE -ne 0) { throw "Unable to commit Studio files" }
    git -C $publishRoot push origin HEAD
    if ($LASTEXITCODE -ne 0) { throw "Unable to push Studio files" }
    Write-Output "ModelScope Studio upload completed."
}
finally {
    if (Test-Path -LiteralPath $publishRoot) {
        Remove-Item -LiteralPath $publishRoot -Recurse -Force
    }
}

