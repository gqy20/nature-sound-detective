param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir $config.sourceRoot))
$outputDir = Join-Path $projectDir "02-proxies/recordings-1080p"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$names = $config.scenes | Where-Object { $_.mode -eq "source" } | Select-Object -ExpandProperty source -Unique

foreach ($name in $names) {
    $inputPath = Join-Path $sourceDir $name
    $outputPath = Join-Path $outputDir (($name -replace "\.mp4$", "") + "-proxy.mp4")
    if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
        Write-Output "Skip existing proxy: $outputPath"
        continue
    }
    Write-Output "Creating proxy: $name"
    & ffmpeg -hide_banner -loglevel error -y -i $inputPath -map 0:v:0 -map "0:a?" -vf "scale=1080:1920:flags=lanczos,fps=30" -c:v libx264 -preset veryfast -crf 25 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create proxy for $name"
    }
}

