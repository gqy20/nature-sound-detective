[CmdletBinding()]
param(
    [string]$OutputDirectory = "artifacts/modelscope-studio"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceRoot = Join-Path $repositoryRoot "deploy/modelscope"
$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputDirectory))
$artifactsRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "artifacts"))

if (-not $outputRoot.StartsWith($artifactsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output directory must stay inside $artifactsRoot"
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $outputRoot | Out-Null

Get-ChildItem -LiteralPath $sourceRoot -Force | Where-Object { $_.Name -ne "tests" } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $outputRoot -Recurse -Force
}

$modelOutput = Join-Path $outputRoot "assets/models"
$labelOutput = Join-Path $outputRoot "assets/labels"
New-Item -ItemType Directory -Path $modelOutput, $labelOutput | Out-Null

@("yamnet.tflite", "yamnet.json", "birdnet.tflite", "birdnet.json", "nonbird.tflite", "nonbird.json") | ForEach-Object {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot "mobile/assets/models/$_") -Destination $modelOutput
}
@("yamnet.csv", "birdnet_hz.json") | ForEach-Object {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot "mobile/assets/labels/$_") -Destination $labelOutput
}

$revision = (git -C $repositoryRoot rev-parse --short HEAD).Trim()
Set-Content -LiteralPath (Join-Path $outputRoot "REVISION") -Value $revision -Encoding UTF8

$forbiddenNames = @(".env", ".env.local", ".git", "__pycache__")
$badNames = Get-ChildItem -LiteralPath $outputRoot -Recurse -Force | Where-Object { $forbiddenNames -contains $_.Name }
if ($badNames) {
    throw "Unsafe files found in build output: $($badNames.FullName -join ', ')"
}

$textExtensions = @(".py", ".md", ".txt", ".css", ".json", ".csv")
$secretPatterns = @("ms-" + "bf", "DASHSCOPE" + "_API_KEY=", "MODELSCOPE" + "_API_TOKEN=")
Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Where-Object { $textExtensions -contains $_.Extension } | ForEach-Object {
    $content = Get-Content -Raw -LiteralPath $_.FullName -Encoding utf8
    foreach ($pattern in $secretPatterns) {
        if ($content.Contains($pattern)) {
            throw "Possible secret found in $($_.FullName)"
        }
    }
}

$size = (Get-ChildItem -LiteralPath $outputRoot -Recurse -File | Measure-Object Length -Sum).Sum
Write-Output "ModelScope Studio assembled at $outputRoot"
Write-Output "Revision: $revision"
Write-Output ("Files: {0}; Size: {1:N1} MB" -f ((Get-ChildItem -LiteralPath $outputRoot -Recurse -File).Count), ($size / 1MB))
