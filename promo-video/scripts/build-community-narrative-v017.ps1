param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$communityRenderer = Join-Path $PSScriptRoot "render_community_narrative.py"
$assistRenderer = Join-Path $PSScriptRoot "render_community_assist_screen.py"
$mapRenderer = Join-Path $PSScriptRoot "render_hangzhou_map_motion.py"
$screenshot = Join-Path $workspaceDir "artifacts/recording-part05-map.png"
$mapSource = Join-Path $workspaceDir "mobile/assets/maps/hangzhou_osm.png"
$audio = Join-Path $projectDir "06-audio/mix/final-mix-v011.wav"

$designDir = Join-Path $projectDir "04-design/fixes-v017"
$rawDir = Join-Path $projectDir "05-motion/debug-v017"
$outputDir = Join-Path $projectDir "08-exports/segments/fixes-v017"
$reviewDir = Join-Path $projectDir "09-qc/community-narrative-v017-2fps"
$assistScreen = Join-Path $designDir "community-assist-screen-v017.png"
New-Item -ItemType Directory -Force -Path $designDir,$rawDir,$outputDir,$reviewDir | Out-Null

foreach ($path in @($python,$communityRenderer,$assistRenderer,$mapRenderer,$screenshot,$mapSource,$audio)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required input: $path" }
}

if ($Force -or -not (Test-Path -LiteralPath $assistScreen)) {
    & $python $assistRenderer $screenshot $assistScreen
    if ($LASTEXITCODE -ne 0) { throw "Failed to prepare assist tab state" }
}

$s10Raw = Join-Path $rawDir "S10-map-clean-v017-1080p-silent.mp4"
$s11Raw = Join-Path $rawDir "S11-city-listening-network-v017-1080p-silent.mp4"
$s12Raw = Join-Path $rawDir "S12-investigator-relay-v017-1080p-silent.mp4"
$s10 = Join-Path $outputDir "S10-map-clean-v017-1080p.mp4"
$s11 = Join-Path $outputDir "S11-city-listening-network-v017-1080p.mp4"
$s12 = Join-Path $outputDir "S12-investigator-relay-v017-1080p.mp4"

if ($Force -or -not (Test-Path -LiteralPath $s10Raw)) {
    & $python $mapRenderer --source $mapSource --output $s10Raw --duration 6 --fps 30 --width 1920 --height 1080 --encoder h264_nvenc
    if ($LASTEXITCODE -ne 0) { throw "Failed to render clean map segment" }
}
if ($Force -or -not (Test-Path -LiteralPath $s11Raw)) {
    & $python $communityRenderer --scene today --source $screenshot --output $s11Raw --duration 9 --encoder h264_nvenc
    if ($LASTEXITCODE -ne 0) { throw "Failed to render city listening network" }
}
if ($Force -or -not (Test-Path -LiteralPath $s12Raw)) {
    & $python $communityRenderer --scene assist --source $assistScreen --output $s12Raw --duration 10 --encoder h264_nvenc
    if ($LASTEXITCODE -ne 0) { throw "Failed to render investigator relay" }
}

$renders = @(
    [pscustomobject]@{ id="S10"; raw=$s10Raw; output=$s10; start=66; duration=6; note="Map title no longer includes the demo-data badge." },
    [pscustomobject]@{ id="S11"; raw=$s11Raw; output=$s11; start=72; duration=9; note="Product UI remains left; right explains the city-wide sound network." },
    [pscustomobject]@{ id="S12"; raw=$s12Raw; output=$s12; start=81; duration=10; note="Product UI remains left; right explains the investigator relay." }
)

foreach ($item in $renders) {
    if ($Force -or -not (Test-Path -LiteralPath $item.output)) {
        & ffmpeg -hide_banner -loglevel error -y -i $item.raw -ss $item.start -t $item.duration -i $audio `
            -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t $item.duration -movflags +faststart $item.output
        if ($LASTEXITCODE -ne 0) { throw "Failed to add synchronized audio to $($item.id)" }
    }
    $sceneReview = Join-Path $reviewDir $item.id
    New-Item -ItemType Directory -Force -Path $sceneReview | Out-Null
    Get-ChildItem -LiteralPath $sceneReview -Filter '*.png' -File | Remove-Item -Force
    & ffmpeg -hide_banner -loglevel error -y -i $item.output -vf "fps=2,scale=960:-2:flags=lanczos" -q:v 2 (Join-Path $sceneReview "frame-%03d.png")
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract 2 fps frames for $($item.id)" }
    $item | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $item.output -Algorithm SHA256).Hash
    $item | Add-Member -NotePropertyName review_frames -NotePropertyValue (Get-ChildItem -LiteralPath $sceneReview -Filter '*.png' -File).Count
    $probe = & ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $item.output | ConvertFrom-Json
    $item | Add-Member -NotePropertyName probe -NotePropertyValue $probe
}

[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"),($renders | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote community narrative debug segments to $outputDir"
