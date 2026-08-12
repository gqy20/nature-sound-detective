param(
    [string]$Version = "v027",
    [string]$VoiceVersion = "v013-105",
    [string]$Encoder = "h264_nvenc",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDir = Join-Path $projectDir "07-edit/debug-segments-$Version"
$outputDir = Join-Path $projectDir "08-exports/1080p"
$reviewDir = Join-Path $projectDir "09-qc/$Version-master-1080p-2fps"
$rough = Join-Path $outputDir "xykw-promo-$Version-1080p-video.mp4"
$final = Join-Path $outputDir "xykw-promo-$Version-1080p.mp4"
$audio = Join-Path $projectDir "06-audio/mix/final-mix-$VoiceVersion.wav"
$manifestPath = Join-Path $outputDir "xykw-promo-$Version-1080p-manifest.json"
$provenancePath = Join-Path $outputDir "xykw-promo-$Version-1080p-provenance.md"
New-Item -ItemType Directory -Force -Path $outputDir, $reviewDir | Out-Null

$sceneNames = [ordered]@{
    S01 = "S01-parent-question-$Version-1080p.mp4"
    S02 = "S02-parent-question-$Version-1080p.mp4"
    S03 = "S03-complete-soundscape-$Version-1080p.mp4"
    S04 = "S04-family-investigation-$Version-1080p.mp4"
    S05 = "S05-sound-evidence-$Version-1080p.mp4"
    S06 = "S06-candidate-not-answer-$Version-1080p.mp4"
    S07 = "S07-qwen-to-action-$Version-1080p.mp4"
    S08 = "S08-ai-field-questions-$Version-1080p.mp4"
    S09 = "S09-investigation-record-$Version-1080p.mp4"
    S10 = "S10-private-to-hangzhou-$Version-1080p.mp4"
    S11 = "S11-family-city-story-$Version-1080p.mp4"
    S12 = "S12-shared-investigation-$Version-1080p.mp4"
    S13 = "S13-wan-postcard-$Version-1080p.mp4"
    S14 = "S14-postcard-memory-$Version-1080p.mp4"
    S15 = "S15-parent-call-to-action-$Version-1080p.mp4"
}

$sceneFiles = @()
foreach ($scene in $config.scenes) {
    $path = Join-Path $sourceDir $sceneNames[$scene.id]
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing scene: $path" }
    $sceneFiles += $path
}
if (-not (Test-Path -LiteralPath $audio)) { throw "Missing final mix: $audio" }

$duration = [double]$config.master.duration
$durationText = $duration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
$fps = [int]$config.master.fps

if ($Force -or -not (Test-Path -LiteralPath $rough)) {
    $arguments = @("-hide_banner", "-loglevel", "error", "-y")
    $filters = @()
    for ($index = 0; $index -lt $sceneFiles.Count; $index++) {
        $arguments += @("-i", $sceneFiles[$index])
        $sceneDuration = [double]$config.scenes[$index].end - [double]$config.scenes[$index].start
        $chain = "[$index`:v]scale=1920:1080:flags=lanczos,setsar=1,fps=$fps,settb=expr=1/$fps,setpts=PTS-STARTPTS"
        if ($index -gt 0) { $chain += ",fade=t=in:st=0:d=0.12:color=0xF3F0E7" }
        if ($index -lt $sceneFiles.Count - 1) {
            $fadeStart = ($sceneDuration - 0.12).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)
            $chain += ",fade=t=out:st=$fadeStart`:d=0.12:color=0xF3F0E7"
        }
        $filters += "$chain[v$index]"
    }
    $concatInputs = (0..($sceneFiles.Count - 1) | ForEach-Object { "[v$_]" }) -join ""
    $filters += "${concatInputs}concat=n=$($sceneFiles.Count):v=1:a=0,trim=duration=$durationText,setpts=PTS-STARTPTS,format=yuv420p[outv]"
    $codec = if ($Encoder -eq "h264_nvenc") {
        @("-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "17", "-b:v", "0")
    } else {
        @("-c:v", "libx264", "-preset", "slow", "-crf", "18")
    }
    $arguments += @("-filter_complex", ($filters -join ";"), "-map", "[outv]", "-an", "-r", $fps)
    $arguments += $codec
    $arguments += @(
        "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709",
        "-color_trc", "bt709", "-movflags", "+faststart", $rough
    )
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed to build master video" }
}

if ($Force -or -not (Test-Path -LiteralPath $final)) {
    & ffmpeg -hide_banner -loglevel error -y -i $rough -i $audio `
        -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 256k -ar 48000 `
        -t $durationText -movflags +faststart $final
    if ($LASTEXITCODE -ne 0) { throw "Failed to mux final master" }
}

Get-ChildItem -LiteralPath $reviewDir -Filter "frame-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
& ffmpeg -hide_banner -loglevel error -y -i $final -vf "fps=2,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 (Join-Path $reviewDir "frame-%03d.jpg")
if ($LASTEXITCODE -ne 0) { throw "Failed final 2fps extraction" }

$probe = & ffprobe -v error -show_entries format=duration,size,bit_rate:stream=codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels,color_space,color_transfer,color_primaries -of json -- $final | ConvertFrom-Json
$sourceAudit = foreach ($path in $sceneFiles) {
    [pscustomobject]@{ path = $path; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
}
$manifest = [pscustomobject]@{
    version = $Version
    voice_version = $VoiceVersion
    output = $final
    duration = [double]$probe.format.duration
    size_bytes = [long]$probe.format.size
    sha256 = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
    audio = $audio
    audio_sha256 = (Get-FileHash -LiteralPath $audio -Algorithm SHA256).Hash
    probe = $probe
    source_scenes = $sourceAudit
    review_frames = (Get-ChildItem -LiteralPath $reviewDir -Filter "frame-*.jpg").Count
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

$provenanceLines = @(
    "# $Version 1080p export provenance",
    "",
    "- Timeline: 15 debug-segments-$Version scenes in video-config.json order.",
    "- Voice: formal-voiceover-$VoiceVersion.wav at one fixed 1.05x generation speed, with no local time stretching.",
    "- Mix: final-mix-$VoiceVersion.wav with narration-ducked music and natural sound.",
    "- Captions: v013-105 real-speech-timed captions burned into each v027 scene.",
    "- Output: 1920x1080, 30 fps, BT.709, AAC 48 kHz, target duration 110 seconds.",
    "- Transitions: 0.12-second paper-white fades at scene boundaries without shortening the timeline."
)
$provenance = $provenanceLines -join [Environment]::NewLine
[IO.File]::WriteAllText($provenancePath, $provenance, [Text.UTF8Encoding]::new($false))

Write-Output "Wrote $final"
Write-Output "Wrote $manifestPath"
Write-Output "Wrote $provenancePath"
