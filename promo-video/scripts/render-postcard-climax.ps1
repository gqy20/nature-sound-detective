param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path (Split-Path -Parent $projectDir) "artifacts/xykw-part06-generated-film-4k.mp4"
$overlay = Join-Path $projectDir "05-motion/editorial/overlays/S14-postcard-overlay-v011.png"
$output = Join-Path $projectDir "05-motion/editorial/postcard-climax-v011.mp4"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Skip existing postcard climax: $output"
    exit 0
}

$filter = "[0:v]split=2[bg0][card0];[bg0]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=34,eq=brightness=-0.25:saturation=0.68[bg];[card0]scale=-2:920:flags=lanczos,pad=iw+20:ih+20:10:10:color=0xF1EDDF[card];[bg][card]overlay=x=1220:y=80:shortest=1[stage];[stage][1:v]overlay=0:0:shortest=1,format=yuv420p[v]"
& ffmpeg -hide_banner -loglevel error -y -ss 1 -t 8 -i $source -loop 1 -t 8 -i $overlay -f lavfi -t 8 -i "anullsrc=r=48000:cl=stereo" -filter_complex $filter -map "[v]" -map 2:a:0 -r 30 -c:v libx264 -preset slow -crf 19 -c:a aac -b:a 128k -shortest -movflags +faststart $output
if ($LASTEXITCODE -ne 0) { throw "Failed to render postcard climax" }
Write-Output "Wrote $output"
