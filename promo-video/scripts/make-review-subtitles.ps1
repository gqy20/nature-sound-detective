$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$lines = Get-Content -LiteralPath (Join-Path $projectDir "00-brief/narration-scenes.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$outputPath = Join-Path $projectDir "07-edit/subtitles/xykw-promo-rough-v001.srt"

function Format-SrtTime([double]$seconds) {
    $span = [TimeSpan]::FromSeconds($seconds)
    return "{0:00}:{1:00}:{2:00},{3:000}" -f [math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds, $span.Milliseconds
}

$blocks = @()
$index = 1
foreach ($scene in $config.scenes) {
    $line = $lines | Where-Object { $_.id -eq $scene.id } | Select-Object -First 1
    if (-not $line) { continue }
    $captionStart = [double]$scene.start + 0.2
    $captionEnd = [double]$scene.end - 0.15
    $blocks += [string]$index
    $blocks += "$(Format-SrtTime $captionStart) --> $(Format-SrtTime $captionEnd)"
    $blocks += [string]$line.text
    $blocks += ""
    $index++
}

[System.IO.File]::WriteAllLines($outputPath, $blocks, [System.Text.UTF8Encoding]::new($true))
Write-Output "Wrote $outputPath"

