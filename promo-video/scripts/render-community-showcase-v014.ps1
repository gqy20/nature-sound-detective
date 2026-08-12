param([switch]$Force, [switch]$AssistOnly)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$outputDir = Join-Path $projectDir "05-motion/4k-v014"
$screenshot = Join-Path $workspaceDir "artifacts/recording-part05-map.png"
$assistScreenshot = Join-Path $outputDir "community-assist-screen-v014.png"
$map = Join-Path $projectDir "05-motion/4k-v013/hangzhou-soundscape-map-v013-4k.mp4"
$todayOutput = Join-Path $outputDir "community-today-v014-4k.mp4"
$assistOutput = Join-Path $outputDir "community-assist-v014-4k.mp4"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if (-not (Test-Path -LiteralPath $screenshot)) { throw "Missing real product screenshot: $screenshot" }
if (-not (Test-Path -LiteralPath $map)) { throw "Missing fixed 4K map: $map" }

& "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" `
    (Join-Path $PSScriptRoot "render_community_assist_screen.py") $screenshot $assistScreenshot
if ($LASTEXITCODE -ne 0) { throw "Failed to prepare assistance tab state" }

if (-not $AssistOnly -and (-not (Test-Path -LiteralPath $todayOutput) -or $Force)) {
    $todayFilter = @"
[0:v]split=2[phone0][detail0];
[phone0]scale=-2:2000:flags=lanczos,format=rgba,fade=t=in:st=0:d=0.55:alpha=1[phone];
[detail0]crop=1020:800:30:180,scale=2150:1686:flags=lanczos,format=rgba,fade=t=in:st=0.55:d=0.7:alpha=1[detail];
[2:v][phone]overlay=220:80:shortest=1[stage1];
[stage1][detail]overlay=1430:238:shortest=1[product0];
[product0]fps=30,settb=1/30,setpts=PTS-STARTPTS[product];
[1:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,format=rgba,fade=t=in:st=3.15:d=0.9:alpha=1[mapFade];
[product][mapFade]overlay=0:0:shortest=1,format=yuv420p[v]
"@
    & ffmpeg -hide_banner -loglevel error -y `
        -loop 1 -framerate 30 -t 9 -i $screenshot `
        -ss 6 -t 9 -i $map `
        -f lavfi -t 9 -i "color=c=#F3F0E7:s=3840x2160:r=30" `
        -f lavfi -t 9 -i "anullsrc=r=48000:cl=stereo" `
        -filter_complex $todayFilter -map "[v]" -map 3:a:0 -t 9 -r 30 `
        -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 15 -b:v 0 `
        -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart $todayOutput
    if ($LASTEXITCODE -ne 0) { throw "Failed to render community today showcase" }
}

if (-not (Test-Path -LiteralPath $assistOutput) -or $Force) {
    $assistFilter = @"
[0:v]split=2[phone0][detail0];
[phone0]scale=-2:2000:flags=lanczos[phone];
[detail0]crop=1020:900:30:850,scale=1850:1632:flags=lanczos[detail];
[2:v][phone]overlay=220:80:shortest=1[stage1];
[stage1][detail]overlay=1870:180:shortest=1[product0];
[product0]fps=30,settb=1/30,setpts=PTS-STARTPTS[product];
[1:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,format=rgba,fade=t=in:st=3.2:d=0.8:alpha=1[map];
[product][map]overlay=0:0:shortest=1,format=yuv420p[v]
"@
    & ffmpeg -hide_banner -loglevel error -y `
        -loop 1 -framerate 30 -t 10 -i $assistScreenshot `
        -ss 15 -t 10 -i $map `
        -f lavfi -t 10 -i "color=c=#F3F0E7:s=3840x2160:r=30" `
        -f lavfi -t 10 -i "anullsrc=r=48000:cl=stereo" `
        -filter_complex $assistFilter -map "[v]" -map 3:a:0 -t 10 -r 30 `
        -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 15 -b:v 0 `
        -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart $assistOutput
    if ($LASTEXITCODE -ne 0) { throw "Failed to render community assistance showcase" }
}

Write-Output "Wrote $todayOutput"
Write-Output "Wrote $assistOutput"
