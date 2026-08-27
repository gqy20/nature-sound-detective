[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryUrl,
    [string]$SpaceDirectory = "artifacts/modelscope-studio",
    [string]$ModelScopeEndpoint = "https://modelscope.cn",
    [int]$DeployTimeoutSeconds = 600
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

$repositoryUri = [Uri]$RepositoryUrl
$pathParts = $repositoryUri.AbsolutePath.Trim("/") -split "/"
if ($pathParts.Count -lt 3 -or $pathParts[0] -ne "studios") {
    throw "RepositoryUrl must look like https://modelscope.cn/studios/<owner>/<repo>.git"
}
$studioOwner = $pathParts[1]
$studioName = [System.IO.Path]::GetFileNameWithoutExtension($pathParts[2])
$studioId = "$studioOwner/$studioName"
$apiRoot = $ModelScopeEndpoint.TrimEnd("/") + "/openapi/v1/studios/$studioOwner/$studioName"
$headers = @{ Authorization = "Bearer $token" }

& (Join-Path $PSScriptRoot "build_modelscope_space.ps1") -OutputDirectory $SpaceDirectory
& (Join-Path $PSScriptRoot "test_modelscope_space.ps1") -SpaceDirectory $SpaceDirectory

$studioConfig = Get-Content -Raw -LiteralPath (Join-Path $spaceRoot "studio_config.py")
$versionMatch = [regex]::Match($studioConfig, '(?m)^VERSION\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) { throw "Unable to read Studio VERSION from studio_config.py" }
$studioVersion = $versionMatch.Groups[1].Value
$studioRevision = (Get-Content -Raw -LiteralPath (Join-Path $spaceRoot "REVISION")).Trim()
if (-not $studioRevision) { throw "Studio REVISION is empty" }

$publishRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nature-sound-detective-modelscope-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $publishRoot | Out-Null
try {
    $authenticated = "{0}://oauth2:{1}@{2}{3}" -f $repositoryUri.Scheme, [Uri]::EscapeDataString($token), $repositoryUri.Authority, $repositoryUri.PathAndQuery
    git clone $authenticated $publishRoot
    if ($LASTEXITCODE -ne 0) { throw "Unable to clone ModelScope Studio repository" }

    Get-ChildItem -LiteralPath $publishRoot -Force | Where-Object { $_.Name -ne ".git" } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    Copy-Item -Path (Join-Path $spaceRoot "*") -Destination $publishRoot -Recurse -Force
    git -C $publishRoot add --all
    git -C $publishRoot diff --cached --quiet
    if ($LASTEXITCODE -ne 0) {
        git -C $publishRoot -c user.name="gqy20" -c user.email="actions@users.noreply.github.com" commit -m "Deploy nature-sound-detective $studioVersion ($studioRevision)"
        if ($LASTEXITCODE -ne 0) { throw "Unable to commit Studio files" }
        git -C $publishRoot push origin HEAD
        if ($LASTEXITCODE -ne 0) { throw "Unable to push Studio files" }
    }
    else {
        Write-Output "Studio source is already up to date; restarting the current revision."
    }

    Invoke-RestMethod -Method Post -Uri "$apiRoot/deploy" -Headers $headers | Out-Null
    Write-Output "Deployment requested for $studioId."

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($DeployTimeoutSeconds)
    $isRunning = $false
    do {
        Start-Sleep -Seconds 8
        $studio = Invoke-RestMethod -Method Get -Uri $apiRoot -Headers $headers
        $statusText = $studio | ConvertTo-Json -Depth 20 -Compress
        if ($statusText -match '(?i)"status"\s*:\s*"(running|deployed|ready)"') {
            $isRunning = $true
            Write-Output "ModelScope Studio is running: $studioId"
            break
        }
        if ($statusText -match '(?i)"status"\s*:\s*"(failed|error|deployfailed|buildfailed)"') {
            throw "ModelScope Studio deployment failed for $studioId. Check the Studio run logs."
        }
        Write-Output "Waiting for Studio deployment..."
    } while ([DateTimeOffset]::UtcNow -lt $deadline)

    if (-not $isRunning) {
        throw "Timed out waiting for ModelScope Studio deployment after $DeployTimeoutSeconds seconds."
    }
}
finally {
    if (Test-Path -LiteralPath $publishRoot) {
        Remove-Item -LiteralPath $publishRoot -Recurse -Force
    }
}
