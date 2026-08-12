param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$motionDir = Join-Path $projectDir "05-motion/4k-v012"
$overlayDir = Join-Path $motionDir "overlays"
$posterDir = Join-Path $projectDir "09-qc/frame-grabs/v012-native-4k"
New-Item -ItemType Directory -Force -Path $motionDir, $overlayDir, $posterDir | Out-Null

function Invoke-Checked([scriptblock]$Command, [string]$Message) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw $Message }
}

function Scale-Overlay([string]$SourceName, [string]$OutputName) {
    $source = Join-Path $projectDir ("05-motion/editorial/overlays/{0}" -f $SourceName)
    $output = Join-Path $overlayDir $OutputName
    if ((Test-Path -LiteralPath $output) -and -not $Force) { return }
    Invoke-Checked { ffmpeg -hide_banner -loglevel error -y -i $source -vf "scale=3840:2160:flags=lanczos" -frames:v 1 $output } "Failed to scale $SourceName"
}

$overlayJobs = @(
    @("S01-opening-title-overlay-v008.png", "S01-opening-title-overlay-v012-4k.png"),
    @("S02-editorial-overlay-v008.png", "S02-editorial-overlay-v012-4k.png"),
    @("S04-editorial-overlay-v010.png", "S04-editorial-overlay-v012-4k.png"),
    @("S05-editorial-overlay-v010.png", "S05-editorial-overlay-v012-4k.png"),
    @("S08-editorial-overlay-v009.png", "S08-editorial-overlay-v012-4k.png"),
    @("S09-editorial-overlay-v010.png", "S09-editorial-overlay-v012-4k.png"),
    @("S13-editorial-overlay-v010.png", "S13-editorial-overlay-v012-4k.png"),
    @("S14-postcard-overlay-v011.png", "S14-postcard-overlay-v012-4k.png")
)
foreach ($job in $overlayJobs) { Scale-Overlay $job[0] $job[1] }

$editorialRenderer = Join-Path $PSScriptRoot "render_editorial_motion.py"
$openingStill = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-v001.png"
$frog = Join-Path $workspaceDir "mobile/assets/species/pelophylax_nigromaculatus.webp"
$insect = Join-Path $workspaceDir "mobile/assets/species/cryptotympana_atrata.webp"
$editorialJobs = @(
    @{ Scene="montage"; Duration=7; Output="multi-sound-montage-v012-4k.mp4"; Poster="S03-v012-4k.jpg" },
    @{ Scene="technology"; Duration=6; Output="technology-evidence-v012-4k.mp4"; Poster="S07-v012-4k.jpg" },
    @{ Scene="brand"; Duration=4; Output="brand-end-card-v012-4k.mp4"; Poster="S15-v012-4k.jpg" }
)
foreach ($job in $editorialJobs) {
    $output = Join-Path $motionDir $job.Output
    if ((Test-Path -LiteralPath $output) -and -not $Force) { continue }
    $arguments = @($editorialRenderer, "--scene", $job.Scene, "--duration", $job.Duration, "--output", $output, "--poster", (Join-Path $posterDir $job.Poster), "--width", 3840, "--height", 2160, "--encoder", "h264_nvenc")
    if ($job.Scene -eq "montage") { $arguments += @("--source", $openingStill, "--frog", $frog, "--insect", $insect) }
    Invoke-Checked { & $python @arguments } "Failed to render native 4K $($job.Scene)"
}

$mapOutput = Join-Path $motionDir "hangzhou-soundscape-map-v012-4k.mp4"
if (-not (Test-Path -LiteralPath $mapOutput) -or $Force) {
    $mapArguments = @(
        (Join-Path $PSScriptRoot "render_hangzhou_map_motion.py"),
        "--source", (Join-Path $workspaceDir "mobile/assets/maps/hangzhou_osm.png"),
        "--output", $mapOutput,
        "--poster", (Join-Path $posterDir "hangzhou-map-v012-4k.jpg"),
        "--duration", 25,
        "--fps", 30,
        "--width", 3840,
        "--height", 2160,
        "--encoder", "h264_nvenc"
    )
    Invoke-Checked { & $python @mapArguments } "Failed to render native 4K Hangzhou map"
}

$analysisLabels = Join-Path $motionDir "analysis-labels-v012-4k.png"
$analysisOutput = Join-Path $motionDir "analysis-waveform-v012-4k.mp4"
if (-not (Test-Path -LiteralPath $analysisOutput) -or $Force) {
    Invoke-Checked { & $python (Join-Path $PSScriptRoot "render_analysis_labels.py") $analysisLabels --width 3840 --height 2160 } "Failed to render native 4K analysis labels"
    $analysisSource = Join-Path $workspaceDir "artifacts/xykw-part01-4k.mp4"
    $audio = Join-Path $workspaceDir "artifacts/xykw-original-sound.wav"
    $analysisFilter = @"
[0:v]scale=-2:2000:flags=lanczos,setsar=1[phone];
[1:v][phone]overlay=(W-w)/2:(H-h)/2:shortest=1[base];
[2:a]atrim=0:10,asetpts=PTS-STARTPTS,asplit=2[a1][a2];
[a1]volume=10,showwaves=s=1040x340:mode=line:rate=30:colors=0x67DA9A:scale=sqrt,format=rgba,colorchannelmixer=aa=0.94[wave];
[a2]volume=6,showspectrum=s=1040x460:mode=combined:color=viridis:scale=sqrt:slide=scroll:fps=30,format=rgba,colorkey=0x000000:0.08:0.12,colorchannelmixer=aa=0.82[spec];
[base][wave]overlay=2640:720[tmp1];
[tmp1][spec]overlay=2640:1180[tmp2];
[tmp2][3:v]overlay=0:0,format=yuv420p[v]
"@
    Invoke-Checked { ffmpeg -hide_banner -loglevel error -y -ss 81 -t 10 -i $analysisSource -f lavfi -t 10 -i "color=c=#F3F0E7:s=3840x2160:r=30" -i $audio -loop 1 -t 10 -i $analysisLabels -filter_complex $analysisFilter -map "[v]" -an -r 30 -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 16 -b:v 0 -pix_fmt yuv420p -movflags +faststart $analysisOutput } "Failed to render native 4K analysis scene"
}

$openingOutput = Join-Path $motionDir "opening-sound-mystery-v012-4k.mp4"
if (-not (Test-Path -LiteralPath $openingOutput) -or $Force) {
    $openingSource = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-video-v001.mp4"
    $openingOverlay = Join-Path $overlayDir "S01-opening-title-overlay-v012-4k.png"
    $openingFilter = "[0:v]scale=3840:2160:force_original_aspect_ratio=increase,crop=3840:2160,setpts=1.19149*PTS[base];[1:v]format=rgba,fade=t=in:st=1.0:d=0.7:alpha=1,fade=t=out:st=5.8:d=0.7:alpha=1[title];[base][title]overlay=0:0:shortest=1,format=yuv420p[v]"
    Invoke-Checked { ffmpeg -hide_banner -loglevel error -y -i $openingSource -loop 1 -t 7 -i $openingOverlay -f lavfi -t 7 -i "anullsrc=r=48000:cl=stereo" -filter_complex $openingFilter -map "[v]" -map 2:a:0 -t 7 -r 30 -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 16 -b:v 0 -c:a aac -b:a 128k -shortest -movflags +faststart $openingOutput } "Failed to render 4K opening"
}

$postcardOutput = Join-Path $motionDir "postcard-climax-v012-4k.mp4"
if (-not (Test-Path -LiteralPath $postcardOutput) -or $Force) {
    $postcardSource = Join-Path $workspaceDir "artifacts/xykw-part06-generated-film-4k.mp4"
    $postcardOverlay = Join-Path $overlayDir "S14-postcard-overlay-v012-4k.png"
    $postcardFilter = "[0:v]split=2[bg0][card0];[bg0]scale=3840:2160:force_original_aspect_ratio=increase,crop=3840:2160,gblur=sigma=68,eq=brightness=-0.25:saturation=0.68[bg];[card0]scale=-2:1840:flags=lanczos,pad=iw+40:ih+40:20:20:color=0xF1EDDF[card];[bg][card]overlay=x=2440:y=160:shortest=1[stage];[stage][1:v]overlay=0:0:shortest=1,format=yuv420p[v]"
    Invoke-Checked { ffmpeg -hide_banner -loglevel error -y -ss 1 -t 8 -i $postcardSource -loop 1 -t 8 -i $postcardOverlay -f lavfi -t 8 -i "anullsrc=r=48000:cl=stereo" -filter_complex $postcardFilter -map "[v]" -map 2:a:0 -r 30 -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 16 -b:v 0 -c:a aac -b:a 128k -shortest -movflags +faststart $postcardOutput } "Failed to render native 4K postcard"
}

Write-Output "Native 4K motion assets are ready in $motionDir"
