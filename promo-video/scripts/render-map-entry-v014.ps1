param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$outputDir = Join-Path $projectDir "05-motion/4k-v014"
$output = Join-Path $outputDir "map-entry-v014-4k.mp4"
$screenshot = Join-Path $workspaceDir "artifacts/recording-part05-map.png"
$map = Join-Path $projectDir "05-motion/4k-v013/hangzhou-soundscape-map-v013-4k.mp4"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Keep existing map entry: $output"
    exit 0
}
if (-not (Test-Path -LiteralPath $screenshot)) { throw "Missing real product screenshot: $screenshot" }
if (-not (Test-Path -LiteralPath $map)) { throw "Missing fixed 4K map: $map" }

# The screenshot is 1080x2400. Its OSM map occupies approximately
# x=48..1056 and y=468..1034. We begin with the complete product screen,
# then zoom that exact region to 16:9 before dissolving into the code map.
$p = "min(max((t-1.0)/1.6\,0)\,1)"
$filter = @"
[0:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,format=rgba,
scale=w='trunc(iw*(0.8333333+2.9761905*$p)/2)*2':h='trunc(ih*(0.8333333+2.9761905*$p)/2)*2':eval=frame[phone];
[2:v]fps=30,settb=1/30,setpts=PTS-STARTPTS[canvas];
[canvas][phone]overlay=x='1470-1653*$p':y='80-1863*$p':shortest=1[phoneStage0];
[phoneStage0]fps=30,settb=1/30,setpts=PTS-STARTPTS[phoneStage];
[1:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,format=rgba,fade=t=in:st=2.2:d=0.8:alpha=1[map];
[phoneStage][map]overlay=0:0:shortest=1,format=yuv420p[v]
"@

& ffmpeg -hide_banner -loglevel error -y `
    -loop 1 -framerate 30 -t 6 -i $screenshot `
    -t 6 -i $map `
    -f lavfi -t 6 -i "color=c=#F3F0E7:s=3840x2160:r=30" `
    -f lavfi -t 6 -i "anullsrc=r=48000:cl=stereo" `
    -filter_complex $filter -map "[v]" -map 3:a:0 -t 6 -r 30 `
    -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 15 -b:v 0 `
    -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart $output
if ($LASTEXITCODE -ne 0) { throw "Failed to render map-entry transition" }

Write-Output "Wrote $output"
