param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-video-v001.mp4"
$overlay = Join-Path $projectDir "05-motion/editorial/overlays/S01-opening-title-overlay-v008.png"
$output = Join-Path $projectDir "05-motion/editorial/opening-sound-mystery-v008.mp4"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
if ((Test-Path -LiteralPath $output) -and -not $Force) { Write-Output "Skip existing opening: $output"; exit 0 }

$filter = "[0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setpts=1.19149*PTS[base];[1:v]format=rgba,fade=t=in:st=1.0:d=0.7:alpha=1,fade=t=out:st=5.8:d=0.7:alpha=1[title];[base][title]overlay=0:0:shortest=1,format=yuv420p[v]"
& ffmpeg -hide_banner -loglevel error -y -i $source -loop 1 -t 7 -i $overlay -f lavfi -t 7 -i "anullsrc=r=48000:cl=stereo" -filter_complex $filter -map "[v]" -map 2:a:0 -t 7 -r 30 -c:v libx264 -preset slow -crf 18 -c:a aac -b:a 128k -shortest -movflags +faststart $output
if ($LASTEXITCODE -ne 0) { throw "Failed to render v004 opening" }
Write-Output "Wrote $output"
