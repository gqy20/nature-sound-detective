param(
    [switch]$Force,
    [string]$Encoder = "h264_nvenc",
    [ValidateRange(1, 4)][int]$Parallel = 2,
    [string[]]$Scenes = @()
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $PSScriptRoot "render_story_scenes_v025.py"
$outputDir = Join-Path $projectDir "07-edit/debug-segments-v025"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$outputs = [ordered]@{
    S02 = "S02-real-sound-device-v025-1080p.mp4"
    S03 = "S03-six-sound-scenes-v025-1080p.mp4"
    S04 = "S04-child-investigator-v025-1080p.mp4"
    S05 = "S05-sound-evidence-v025-1080p.mp4"
    S06 = "S06-acoustic-analysis-v025-1080p.mp4"
    S07 = "S07-readable-technology-v025-1080p.mp4"
    S08 = "S08-ai-field-questions-v025-1080p.mp4"
    S09 = "S09-investigation-record-v025-1080p.mp4"
    S10 = "S10-phone-to-hangzhou-v025-1080p.mp4"
    S13 = "S13-ai-cocreation-growth-v025-1080p.mp4"
    S15 = "S15-brand-wave-converge-v025-1080p.mp4"
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
            '--encoder', $Encoder
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
    $probe = & ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $output | ConvertFrom-Json
    [pscustomobject]@{
        id = $scene
        output = $output
        sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        probe = $probe
    }
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"), ($manifest | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))
Write-Output "Wrote v025 scene set to $outputDir"
