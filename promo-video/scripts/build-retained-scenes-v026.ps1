param(
    [switch]$Force,
    [string]$Encoder = "h264_nvenc",
    [ValidateRange(1, 4)][int]$Parallel = 2,
    [string]$VoiceVersion = "v013-105",
    [string]$BuildVersion = "v027"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $projectDir "07-edit/debug-segments-$BuildVersion"
$reviewDir = Join-Path $projectDir "09-qc/story-scenes-$BuildVersion-2fps"
$subtitleDir = Join-Path $projectDir "07-edit/subtitles/$VoiceVersion-scenes"
$voiceDir = Join-Path $projectDir "06-audio/voiceover/formal/scenes/$VoiceVersion"
New-Item -ItemType Directory -Force -Path $outputDir, $reviewDir | Out-Null

$jobs = @(
    [pscustomobject]@{
        Id = "S01"; Duration = 7
        Source = Join-Path $projectDir "05-motion/editorial/opening-sound-mystery-v008.mp4"
        Output = Join-Path $outputDir "S01-parent-question-$BuildVersion-1080p.mp4"
    },
    [pscustomobject]@{
        Id = "S11"; Duration = 9
        Source = Join-Path $projectDir "05-motion/4k-v014/community-today-v014-4k.mp4"
        Output = Join-Path $outputDir "S11-family-city-story-$BuildVersion-1080p.mp4"
    },
    [pscustomobject]@{
        Id = "S12"; Duration = 10
        Source = Join-Path $projectDir "05-motion/4k-v014/community-assist-v014-4k.mp4"
        Output = Join-Path $outputDir "S12-shared-investigation-$BuildVersion-1080p.mp4"
    },
    [pscustomobject]@{
        Id = "S14"; Duration = 8
        Source = Join-Path $projectDir "05-motion/editorial/postcard-climax-v011.mp4"
        Output = Join-Path $outputDir "S14-postcard-memory-$BuildVersion-1080p.mp4"
    }
)

$queue = [Collections.Queue]::new()
foreach ($job in $jobs) {
    if (-not (Test-Path -LiteralPath $job.Source)) { throw "Missing source: $($job.Source)" }
    $voice = Join-Path $voiceDir "$($job.Id)-voice.wav"
    $subtitle = Join-Path $subtitleDir "$($job.Id).ass"
    if (-not (Test-Path -LiteralPath $voice)) { throw "Missing voice: $voice" }
    if (-not (Test-Path -LiteralPath $subtitle)) { throw "Missing subtitles: $subtitle" }
    if ((Test-Path -LiteralPath $job.Output) -and -not $Force) {
        Write-Output "Keep $($job.Id)"
        continue
    }
    $job | Add-Member -NotePropertyName Voice -NotePropertyValue $voice
    $job | Add-Member -NotePropertyName Subtitle -NotePropertyValue $subtitle
    $queue.Enqueue($job)
}

$active = @()
while ($queue.Count -gt 0 -or $active.Count -gt 0) {
    while ($queue.Count -gt 0 -and $active.Count -lt $Parallel) {
        $job = $queue.Dequeue()
        $relativeSubtitle = "07-edit/subtitles/$VoiceVersion-scenes/$($job.Id).ass"
        $filter = "scale=1920:1080:flags=lanczos,fps=30,tpad=stop_mode=clone:stop_duration=1,trim=duration=$($job.Duration),ass=filename='$relativeSubtitle',format=yuv420p"
        $arguments = @(
            "-hide_banner", "-loglevel", "error", "-y",
            "-i", ('"' + $job.Source + '"'),
            "-i", ('"' + $job.Voice + '"'),
            "-vf", ('"' + $filter + '"'),
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", $Encoder, "-preset", "p5", "-cq", "18",
            "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
            "-t", $job.Duration, "-movflags", "+faststart",
            ('"' + $job.Output + '"')
        )
        Write-Output "Render $($job.Id) [$($active.Count + 1)/$Parallel]"
        $process = Start-Process -FilePath ffmpeg -ArgumentList $arguments -WorkingDirectory $projectDir -PassThru -WindowStyle Hidden
        $active += [pscustomobject]@{ Job = $job; Process = $process }
    }

    if ($active.Count -gt 0) {
        Wait-Process -Id $active[0].Process.Id
        $remaining = @()
        foreach ($item in $active) {
            if ($item.Process.HasExited) {
                if ($item.Process.ExitCode -ne 0) { throw "Failed to render $($item.Job.Id)" }
                if (-not (Test-Path -LiteralPath $item.Job.Output)) { throw "Missing output for $($item.Job.Id)" }
                Write-Output "Done $($item.Job.Id)"
            } else {
                $remaining += $item
            }
        }
        $active = $remaining
    }
}

foreach ($job in $jobs) {
    $sceneReview = Join-Path $reviewDir $job.Id
    New-Item -ItemType Directory -Force -Path $sceneReview | Out-Null
    Get-ChildItem -LiteralPath $sceneReview -Filter "frame-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
    & ffmpeg -hide_banner -loglevel error -y -i $job.Output -vf "fps=2:start_time=0,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 (Join-Path $sceneReview "frame-%03d.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed 2fps extraction for $($job.Id)" }
    & ffmpeg -hide_banner -loglevel error -y -i $job.Output -vf "fps=2:start_time=0,scale=384:216:flags=lanczos,tile=5x5:nb_frames=25:padding=8:margin=12:color=0x171A18" -frames:v 1 -q:v 2 (Join-Path $reviewDir "$($job.Id)-contact.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed contact sheet for $($job.Id)" }
}

$completeManifest = foreach ($file in Get-ChildItem -LiteralPath $outputDir -Filter "S??-*-$BuildVersion-1080p.mp4" | Sort-Object Name) {
    $probe = & ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels,duration -of json -- $file.FullName | ConvertFrom-Json
    [pscustomobject]@{
        id = $file.Name.Substring(0, 3)
        output = $file.FullName
        voice_version = $VoiceVersion
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        probe = $probe
    }
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest-complete.json"), ($completeManifest | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

Write-Output "Wrote retained $BuildVersion scenes to $outputDir"
Write-Output "Wrote complete manifest and 2fps review"
