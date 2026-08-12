param(
    [ValidateRange(1, 4)][int]$Parallel = 2,
    [string]$Encoder = "h264_nvenc",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $PSScriptRoot "render_story_scenes_v025.py"
$sourceS11 = Join-Path $projectDir "05-motion/4k-v014/community-today-v014-4k.mp4"
$outputDir = Join-Path $projectDir "07-edit/speed-ab-v013"
$reviewDir = Join-Path $projectDir "09-qc/speed-ab-v013-2fps"
New-Item -ItemType Directory -Force -Path $outputDir, $reviewDir | Out-Null

$versions = @(
    [pscustomobject]@{ Version = "v013-105"; Label = "105"; Speed = 1.05 },
    [pscustomobject]@{ Version = "v013-110"; Label = "110"; Speed = 1.10 }
)

$jobs = [Collections.Queue]::new()
foreach ($version in $versions) {
    foreach ($scene in @("S05", "S08")) {
        $output = Join-Path $outputDir ("{0}-speed-{1}-1080p.mp4" -f $scene, $version.Label)
        $jobs.Enqueue([pscustomobject]@{
            Id = "$scene-$($version.Label)"; Type = "python"; Scene = $scene
            Version = $version.Version; Speed = $version.Speed; Output = $output
        })
    }
    $jobs.Enqueue([pscustomobject]@{
        Id = "S11-$($version.Label)"; Type = "ffmpeg"; Scene = "S11"
        Version = $version.Version; Speed = $version.Speed
        Output = Join-Path $outputDir ("S11-speed-{0}-1080p.mp4" -f $version.Label)
    })
}

$active = @()
while ($jobs.Count -gt 0 -or $active.Count -gt 0) {
    while ($jobs.Count -gt 0 -and $active.Count -lt $Parallel) {
        $job = $jobs.Dequeue()
        if ((Test-Path -LiteralPath $job.Output) -and -not $Force) {
            Write-Output "Keep $($job.Id)"
            continue
        }
        if ($job.Type -eq "python") {
            $arguments = @(
                ('"' + $renderer + '"'), "--scene", $job.Scene,
                "--output", ('"' + $job.Output + '"'),
                "--encoder", $Encoder, "--voice-version", $job.Version
            )
            $process = Start-Process -FilePath python -ArgumentList $arguments -WorkingDirectory $projectDir -PassThru -WindowStyle Hidden
        } else {
            $voice = Join-Path $projectDir "06-audio/voiceover/formal/scenes/$($job.Version)/S11-voice.wav"
            $subtitle = "07-edit/subtitles/$($job.Version)-scenes/S11.ass"
            $filter = "scale=1920:1080:flags=lanczos,fps=30,ass=filename='$subtitle',format=yuv420p"
            $arguments = @(
                "-hide_banner", "-loglevel", "error", "-y",
                "-i", ('"' + $sourceS11 + '"'), "-i", ('"' + $voice + '"'),
                "-vf", ('"' + $filter + '"'), "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", $Encoder, "-preset", "p5", "-cq", "18",
                "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-t", "9",
                "-movflags", "+faststart", ('"' + $job.Output + '"')
            )
            $process = Start-Process -FilePath ffmpeg -ArgumentList $arguments -WorkingDirectory $projectDir -PassThru -WindowStyle Hidden
        }
        Write-Output "Render $($job.Id) [$($active.Count + 1)/$Parallel]"
        $active += [pscustomobject]@{ Job = $job; Process = $process }
    }
    if ($active.Count -gt 0) {
        Wait-Process -Id $active[0].Process.Id
        $remaining = @()
        foreach ($item in $active) {
            if ($item.Process.HasExited) {
                if ($item.Process.ExitCode -ne 0) { throw "Failed $($item.Job.Id)" }
                Write-Output "Done $($item.Job.Id)"
            } else {
                $remaining += $item
            }
        }
        $active = $remaining
    }
}

$manifest = foreach ($version in $versions) {
    foreach ($scene in @("S05", "S08", "S11")) {
        $file = Join-Path $outputDir ("{0}-speed-{1}-1080p.mp4" -f $scene, $version.Label)
        $probe = & ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels,duration -of json -- $file | ConvertFrom-Json
        $timing = Get-Content -LiteralPath (Join-Path $projectDir "06-audio/voiceover/formal/voiceover-timing-$($version.Version).json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $sceneTiming = $timing.scenes | Where-Object { $_.id -eq $scene } | Select-Object -First 1
        [pscustomobject]@{
            id = $scene; speed = $version.Speed; file = $file
            tail_after_audio = [math]::Round(([double]$sceneTiming.scene_duration - 0.2 - [double]$sceneTiming.raw_duration), 3)
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            probe = $probe
        }
    }
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"), ($manifest | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

foreach ($item in $manifest) {
    $stem = "{0}-{1}" -f $item.id, ([int]([double]$item.speed * 100))
    $sceneReview = Join-Path $reviewDir $stem
    New-Item -ItemType Directory -Force -Path $sceneReview | Out-Null
    Get-ChildItem -LiteralPath $sceneReview -Filter "frame-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
    & ffmpeg -hide_banner -loglevel error -y -i $item.file -vf "fps=2,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 (Join-Path $sceneReview "frame-%03d.jpg")
    & ffmpeg -hide_banner -loglevel error -y -i $item.file -vf "fps=2,scale=384:216:flags=lanczos,tile=5x5:nb_frames=25:padding=8:margin=12:color=0x171A18" -frames:v 1 -q:v 2 (Join-Path $reviewDir "$stem-contact.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed review output for $stem" }
}

Write-Output "Wrote speed A/B clips to $outputDir"
