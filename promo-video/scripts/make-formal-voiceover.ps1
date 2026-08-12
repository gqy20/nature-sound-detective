param(
    [switch]$Force,
    [switch]$Reprocess,
    [string]$Voice = "Chinese (Mandarin)_Warm_Girl",
    [string]$Version = "v013-105",
    [double]$Speed = 1.05,
    [string[]]$SceneIds
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$lines = Get-Content -LiteralPath (Join-Path $projectDir "00-brief/narration-scenes.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$rawDir = Join-Path $projectDir ("06-audio/voiceover/formal/raw/{0}" -f $Version)
$sceneDir = Join-Path $projectDir ("06-audio/voiceover/formal/scenes/{0}" -f $Version)
$outputPath = Join-Path $projectDir ("06-audio/voiceover/formal/formal-voiceover-{0}.wav" -f $Version)
$concatTempPath = Join-Path $projectDir ("06-audio/voiceover/formal/formal-voiceover-{0}-concat.wav" -f $Version)
$concatPath = Join-Path $projectDir ("07-edit/timelines/formal-voiceover-concat-{0}.txt" -f $Version)
$manifestPath = Join-Path $projectDir ("06-audio/voiceover/formal/voiceover-timing-{0}.json" -f $Version)
$leadInSeconds = 0.20
$tailRoomSeconds = 0.12
New-Item -ItemType Directory -Force -Path $rawDir, $sceneDir, (Split-Path -Parent $concatPath) | Out-Null

if (-not (Get-Command mmx -ErrorAction SilentlyContinue)) {
    throw "mmx is required for the formal voiceover"
}
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue) -or -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffmpeg and ffprobe are required for the formal voiceover"
}

$sceneFiles = @()
$timings = @()
foreach ($scene in $config.scenes) {
    $line = $lines | Where-Object { $_.id -eq $scene.id } | Select-Object -First 1
    if (-not $line) { throw "Missing narration for $($scene.id)" }
    $duration = [double]$scene.end - [double]$scene.start
    $availableSpeech = $duration - $leadInSeconds - $tailRoomSeconds
    $rawPath = Join-Path $rawDir ("$($scene.id)-raw.wav")
    $rawSubtitlePath = [System.IO.Path]::ChangeExtension($rawPath, ".srt")
    $scenePath = Join-Path $sceneDir ("$($scene.id)-voice.wav")
    $sceneFiles += $scenePath
    $ttsText = if ($line.tts_text) { [string]$line.tts_text } else { [string]$line.text }
    $regenerate = $Force -or ($SceneIds -and $SceneIds -contains $scene.id)

    if (-not (Test-Path -LiteralPath $rawPath) -or $regenerate) {
        Write-Output "Synthesizing fixed-speed narration $($scene.id) at ${Speed}x"
        $arguments = @(
            "speech", "synthesize",
            "--text", $ttsText,
            "--model", "speech-2.8-hd",
            "--voice", $Voice,
            "--speed", $Speed,
            "--pitch", 0,
            "--volume", 1,
            "--language", "Chinese",
            "--format", "wav",
            "--sample-rate", 44100,
            "--channels", 1,
            "--subtitles",
            "--pronunciation", "Omni/(ˈɒmni)",
            "--out", $rawPath,
            "--non-interactive",
            "--quiet"
        )
        & mmx @arguments
        if ($LASTEXITCODE -ne 0) { throw "MiniMax narration failed for $($scene.id)" }
    }

    $rawDurationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- $rawPath
    $rawDuration = [double]::Parse($rawDurationText, [Globalization.CultureInfo]::InvariantCulture)
    $overflow = $rawDuration - $availableSpeech
    if ($overflow -gt 0.04) {
        throw ("Narration {0} is {1:N2}s too long for its {2:N2}s scene. Revise copy or extend the video; time-stretching is disabled." -f $scene.id, $overflow, $duration)
    }

    if (-not (Test-Path -LiteralPath $scenePath) -or $regenerate -or $Reprocess) {
        $delayMs = [math]::Round($leadInSeconds * 1000)
        $filter = "highpass=f=75,lowpass=f=14500,loudnorm=I=-20:TP=-3:LRA=7,adelay=$delayMs|$delayMs,apad"
        & ffmpeg -hide_banner -loglevel error -y -i $rawPath -filter:a $filter -t $duration -ar 48000 -ac 2 -c:a pcm_s24le $scenePath
        if ($LASTEXITCODE -ne 0) { throw "Failed to process formal narration for $($scene.id)" }
    }

    $timings += [pscustomobject]@{
        id = $scene.id
        scene_start = [double]$scene.start
        scene_end = [double]$scene.end
        scene_duration = $duration
        speech_start = [double]$scene.start + $leadInSeconds
        raw_duration = [math]::Round($rawDuration, 3)
        available_speech = [math]::Round($availableSpeech, 3)
        tail_slack = [math]::Round($availableSpeech - $rawDuration, 3)
        source_subtitles = if (Test-Path -LiteralPath $rawSubtitlePath) { $rawSubtitlePath } else { "" }
        speed = $Speed
        time_stretch = 1.0
    }
}

$concatLines = $sceneFiles | ForEach-Object { "file '$($_.Replace("'", "''"))'" }
[System.IO.File]::WriteAllLines($concatPath, $concatLines, [System.Text.UTF8Encoding]::new($false))
& ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i $concatPath -c:a pcm_s24le -ar 48000 -ac 2 $concatTempPath
if ($LASTEXITCODE -ne 0) { throw "Failed to concatenate formal voiceover" }
$masterDuration = [double]$config.master.duration
& ffmpeg -hide_banner -loglevel error -y -i $concatTempPath -af "apad,atrim=duration=$masterDuration" -c:a pcm_s24le -ar 48000 -ac 2 $outputPath
if ($LASTEXITCODE -ne 0) { throw "Failed to pad formal voiceover to master duration" }
Remove-Item -LiteralPath $concatTempPath

$manifest = [pscustomobject]@{
    version = $Version
    model = "speech-2.8-hd"
    voice = $Voice
    speed = $Speed
    language_boost = "Chinese"
    source_format = "wav"
    source_sample_rate = 44100
    source_channels = 1
    output_sample_rate = 48000
    output_channels = 2
    per_scene_time_stretch = $false
    master_duration = $masterDuration
    scenes = $timings
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $outputPath"
Write-Output "Wrote $manifestPath"
