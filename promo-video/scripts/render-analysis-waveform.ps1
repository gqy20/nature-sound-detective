param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$source = Join-Path $workspaceDir "artifacts/xykw-part01-4k.mp4"
$audio = Join-Path $workspaceDir "artifacts/xykw-original-sound.wav"
$output = Join-Path $projectDir "05-motion/editorial/analysis-waveform-v009.mp4"
$labelRenderer = Join-Path $PSScriptRoot "render_analysis_labels.py"
$labelOverlay = Join-Path $projectDir "05-motion/editorial/analysis-labels-v009.png"
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Skip existing analysis scene: $output"
    exit 0
}

& $python $labelRenderer $labelOverlay
if ($LASTEXITCODE -ne 0) { throw "Failed to render analysis label overlay" }

$filter = @"
[0:v]scale=-2:1000:flags=lanczos,setsar=1[phone];
[1:v][phone]overlay=(W-w)/2:(H-h)/2:shortest=1[base];
[2:a]atrim=0:10,asetpts=PTS-STARTPTS,asplit=2[a1][a2];
[a1]volume=10,showwaves=s=520x170:mode=line:rate=30:colors=0x67DA9A:scale=sqrt,format=rgba,colorchannelmixer=aa=0.94[wave];
[a2]volume=6,showspectrum=s=520x230:mode=combined:color=viridis:scale=sqrt:slide=scroll:fps=30,format=rgba,colorkey=0x000000:0.08:0.12,colorchannelmixer=aa=0.82[spec];
[base][wave]overlay=1320:360[tmp1];
[tmp1][spec]overlay=1320:590[tmp2];
[tmp2][3:v]overlay=0:0,format=yuv420p[v]
"@

& ffmpeg -hide_banner -loglevel error -y -ss 81 -t 10 -i $source -f lavfi -t 10 -i "color=c=#F3F0E7:s=1920x1080:r=30" -i $audio -loop 1 -t 10 -i $labelOverlay -filter_complex $filter -map "[v]" -an -r 30 -c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p -movflags +faststart $output
if ($LASTEXITCODE -ne 0) { throw "Failed to render analysis waveform scene" }
Write-Output "Wrote $output"
