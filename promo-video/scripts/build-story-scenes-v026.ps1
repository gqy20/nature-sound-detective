param(
    [switch]$Force,
    [string]$Encoder = "h264_nvenc",
    [ValidateRange(1, 4)][int]$Parallel = 2,
    [string[]]$Scenes = @(),
    [string]$VoiceVersion = "v013-105",
    [string]$BuildVersion = "v027"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $PSScriptRoot "render_story_scenes_v025.py"
$outputDir = Join-Path $projectDir "07-edit/debug-segments-$BuildVersion"
$reviewDir = Join-Path $projectDir "09-qc/story-scenes-$BuildVersion-2fps"
New-Item -ItemType Directory -Force -Path $outputDir, $reviewDir | Out-Null

$outputs = [ordered]@{
    S02 = "S02-parent-question-$BuildVersion-1080p.mp4"
    S03 = "S03-complete-soundscape-$BuildVersion-1080p.mp4"
    S04 = "S04-family-investigation-$BuildVersion-1080p.mp4"
    S05 = "S05-sound-evidence-$BuildVersion-1080p.mp4"
    S06 = "S06-candidate-not-answer-$BuildVersion-1080p.mp4"
    S07 = "S07-qwen-to-action-$BuildVersion-1080p.mp4"
    S08 = "S08-ai-field-questions-$BuildVersion-1080p.mp4"
    S09 = "S09-investigation-record-$BuildVersion-1080p.mp4"
    S10 = "S10-private-to-hangzhou-$BuildVersion-1080p.mp4"
    S13 = "S13-wan-postcard-$BuildVersion-1080p.mp4"
    S15 = "S15-parent-call-to-action-$BuildVersion-1080p.mp4"
}

$targetScenes = if ($Scenes.Count -gt 0) { $Scenes } else { @($outputs.Keys) }
foreach ($scene in $targetScenes) {
    if (-not $outputs.Contains($scene)) { throw "Unknown scene: $scene" }
}

$queue = [Collections.Queue]::new()
foreach ($scene in $targetScenes) {
    $output = Join-Path $outputDir $outputs[$scene]
    if ((Test-Path -LiteralPath $output) -and -not $Force) {
        Write-Output "Keep $scene"
        continue
    }
    $queue.Enqueue([pscustomobject]@{ Scene = $scene; Output = $output })
}

$active = @()
while ($queue.Count -gt 0 -or $active.Count -gt 0) {
    while ($queue.Count -gt 0 -and $active.Count -lt $Parallel) {
        $item = $queue.Dequeue()
        Write-Output "Render $($item.Scene) [$($active.Count + 1)/$Parallel]"
        $arguments = @(
            ('"' + $renderer + '"'),
            '--scene', $item.Scene,
            '--output', ('"' + $item.Output + '"'),
            '--encoder', $Encoder,
            '--voice-version', $VoiceVersion
        )
        $process = Start-Process -FilePath python -ArgumentList $arguments -PassThru -WindowStyle Hidden
        $active += [pscustomobject]@{ Scene = $item.Scene; Output = $item.Output; Process = $process }
    }

    if ($active.Count -gt 0) {
        Wait-Process -Id $active[0].Process.Id
        $remaining = @()
        foreach ($item in $active) {
            if ($item.Process.HasExited) {
                if ($item.Process.ExitCode -ne 0) { throw "Failed to render $($item.Scene)" }
                if (-not (Test-Path -LiteralPath $item.Output)) { throw "Missing output for $($item.Scene)" }
                Write-Output "Done $($item.Scene)"
            } else {
                $remaining += $item
            }
        }
        $active = $remaining
    }
}

$manifest = foreach ($scene in $outputs.Keys) {
    $output = Join-Path $outputDir $outputs[$scene]
    if (-not (Test-Path -LiteralPath $output)) { continue }
    $probe = & ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels,duration -of json -- $output | ConvertFrom-Json
    [pscustomobject]@{
        id = $scene
        output = $output
        voice_version = $VoiceVersion
        sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        probe = $probe
    }
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"), ($manifest | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

foreach ($scene in $targetScenes) {
    $output = Join-Path $outputDir $outputs[$scene]
    $sceneReview = Join-Path $reviewDir $scene
    New-Item -ItemType Directory -Force -Path $sceneReview | Out-Null
    & ffmpeg -hide_banner -loglevel error -y -i $output -vf "fps=2:start_time=0,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 (Join-Path $sceneReview "frame-%03d.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed 2fps extraction for $scene" }
    & ffmpeg -hide_banner -loglevel error -y -i $output -vf "fps=2:start_time=0,scale=384:216:flags=lanczos,tile=5x5:nb_frames=25:padding=8:margin=12:color=0x171A18" -frames:v 1 -q:v 2 (Join-Path $reviewDir "$scene-contact.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed contact sheet for $scene" }
}

Write-Output "Wrote $BuildVersion scene set to $outputDir"
Write-Output "Wrote 2fps review to $reviewDir"
