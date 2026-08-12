param(
    [string]$Version = "v001",
    [string]$AudioPath,
    [string]$OutputName
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$videoPath = Join-Path $projectDir ("08-exports/review/xykw-promo-rough-{0}.mp4" -f $Version)
$voicePath = if ($AudioPath) { [System.IO.Path]::GetFullPath($AudioPath) } else { Join-Path $projectDir "06-audio/voiceover/temporary/rough-voiceover-v001.wav" }
$subtitlePath = Join-Path $projectDir "07-edit/subtitles/xykw-promo-rough-v001.srt"
$outputPath = if ($OutputName) { Join-Path $projectDir ("08-exports/review/{0}" -f $OutputName) } else { Join-Path $projectDir ("08-exports/review/xykw-promo-rough-vo-{0}.mp4" -f $Version) }

foreach ($required in @($videoPath, $voicePath, $subtitlePath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing required file: $required"
    }
}

& ffmpeg -hide_banner -loglevel error -y -i $videoPath -i $voicePath -i $subtitlePath -map 0:v:0 -map 1:a:0 -map 2:0 -c:v copy -c:a aac -b:a 160k -ar 48000 -c:s mov_text -metadata:s:s:0 language=zho -shortest -movflags +faststart $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to mux review video"
}
Write-Output "Wrote $outputPath"
