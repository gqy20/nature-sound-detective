param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$proxyDir = Join-Path $projectDir "02-proxies/recordings-1080p"
$outputDir = Join-Path $projectDir "02-proxies/contact-sheets"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

foreach ($proxy in Get-ChildItem -LiteralPath $proxyDir -File -Filter "*.mp4") {
    $outputPath = Join-Path $outputDir ($proxy.BaseName + "-contact.jpg")
    if ((Test-Path -LiteralPath $outputPath) -and -not $Force) {
        Write-Output "Skip existing contact sheet: $outputPath"
        continue
    }
    $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- $proxy.FullName
    $duration = [double]::Parse($durationText, [Globalization.CultureInfo]::InvariantCulture)
    $interval = [math]::Max(5, [math]::Ceiling($duration / 28))
    Write-Output "Creating contact sheet: $($proxy.Name), interval ${interval}s"
    & ffmpeg -hide_banner -loglevel error -y -i $proxy.FullName -vf "fps=1/$interval,scale=180:320:flags=lanczos,tile=6x5:padding=4:margin=4" -frames:v 1 -q:v 3 $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create contact sheet for $($proxy.Name)"
    }
}

