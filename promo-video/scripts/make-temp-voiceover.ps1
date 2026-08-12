param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$lines = Get-Content -LiteralPath (Join-Path $projectDir "00-brief/narration-scenes.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$rawDir = Join-Path $projectDir "06-audio/voiceover/temporary/raw"
$sceneDir = Join-Path $projectDir "06-audio/voiceover/temporary/scenes"
$outputPath = Join-Path $projectDir "06-audio/voiceover/temporary/rough-voiceover-v001.wav"
$concatPath = Join-Path $projectDir "07-edit/timelines/rough-voiceover-concat.txt"
New-Item -ItemType Directory -Force -Path $rawDir, $sceneDir, (Split-Path -Parent $concatPath) | Out-Null

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$synth.SelectVoice("Microsoft Huihui Desktop")
$synth.Rate = -1
$synth.Volume = 100
$sceneFiles = @()

foreach ($scene in $config.scenes) {
    $line = $lines | Where-Object { $_.id -eq $scene.id } | Select-Object -First 1
    if (-not $line) {
        throw "Missing narration for $($scene.id)"
    }
    $duration = [double]$scene.end - [double]$scene.start
    $rawPath = Join-Path $rawDir ("$($scene.id)-raw.wav")
    $scenePath = Join-Path $sceneDir ("$($scene.id)-voice.wav")
    $sceneFiles += $scenePath
    if ((Test-Path -LiteralPath $scenePath) -and -not $Force) {
        Write-Output "Skip existing voice scene: $($scene.id)"
        continue
    }

    Write-Output "Synthesizing $($scene.id)"
    $synth.SetOutputToWaveFile($rawPath)
    $synth.Speak([string]$line.text)
    $synth.SetOutputToNull()

    $rawDurationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 -- $rawPath
    $rawDuration = [double]::Parse($rawDurationText, [Globalization.CultureInfo]::InvariantCulture)
    $targetSpeech = [math]::Max(0.5, $duration - 0.5)
    $speed = [math]::Max(1.0, $rawDuration / $targetSpeech)
    if ($speed -gt 2.0) {
        $first = 2.0
        $second = $speed / 2.0
        $tempo = "atempo=$first,atempo=$second"
    } else {
        $tempo = "atempo=$speed"
    }
    $filter = "$tempo,adelay=250|250,apad"
    & ffmpeg -hide_banner -loglevel error -y -i $rawPath -filter:a $filter -t $duration -ar 48000 -ac 2 -c:a pcm_s16le $scenePath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to process narration for $($scene.id)"
    }
}
$synth.Dispose()

$concatLines = $sceneFiles | ForEach-Object { "file '$($_.Replace("'", "''"))'" }
[System.IO.File]::WriteAllLines($concatPath, $concatLines, [System.Text.UTF8Encoding]::new($false))
& ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i $concatPath -c:a pcm_s16le -ar 48000 -ac 2 $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to concatenate temporary voiceover"
}
Write-Output "Wrote $outputPath"

