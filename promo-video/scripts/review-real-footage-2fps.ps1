param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $projectDir "01-source"
$reviewRoot = Join-Path $projectDir "09-qc/source-review-2fps-v001"
$sources = @("wudong.mp4", "21630a.mp4", "bdc47.mp4")
New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null

$manifest = @()
foreach ($name in $sources) {
    $source = Join-Path $sourceDir $name
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    $clipDir = Join-Path $reviewRoot $stem
    $frameDir = Join-Path $clipDir "frames"
    $sheetDir = Join-Path $clipDir "sheets"
    New-Item -ItemType Directory -Force -Path $frameDir, $sheetDir | Out-Null

    $probe = & ffprobe -v error -show_entries format=duration -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -of json -- $source | ConvertFrom-Json
    $duration = [double]$probe.format.duration
    # fps=2 emits frames on the half-second grid strictly inside the source.
    # Floor therefore matches FFmpeg's real output for clips ending between ticks.
    $expectedFrames = [math]::Floor($duration * 2)

    if ($Force -or -not (Get-ChildItem $frameDir -Filter "frame-*.jpg" -ErrorAction SilentlyContinue)) {
        & ffmpeg -hide_banner -loglevel error -y -i $source `
            -vf "fps=2:start_time=0,scale=960:540:flags=lanczos" `
            -q:v 2 -start_number 0 (Join-Path $frameDir "frame-%04d.jpg")
        if ($LASTEXITCODE -ne 0) { throw "Failed 2fps frame extraction: $name" }
    }

    if ($Force -or -not (Get-ChildItem $sheetDir -Filter "sheet-*.jpg" -ErrorAction SilentlyContinue)) {
        & ffmpeg -hide_banner -loglevel error -y -i $source `
            -vf "fps=2:start_time=0,scale=480:270:flags=lanczos,tile=5x4:nb_frames=20:padding=8:margin=12:color=0xF3F0E7" `
            -q:v 2 -vsync 0 -start_number 1 (Join-Path $sheetDir "sheet-%02d.jpg")
        if ($LASTEXITCODE -ne 0) { throw "Failed 2fps contact sheets: $name" }
    }

    $frameFiles = Get-ChildItem $frameDir -Filter "frame-*.jpg" | Sort-Object Name
    $timeIndex = for ($index = 0; $index -lt $frameFiles.Count; $index++) {
        [pscustomobject]@{ frame = $frameFiles[$index].Name; time_seconds = $index / 2.0 }
    }
    [IO.File]::WriteAllText((Join-Path $clipDir "time-index.json"), ($timeIndex | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))

    $manifest += [pscustomobject]@{
        source = $source
        duration_seconds = $duration
        source_width = [int]$probe.streams[0].width
        source_height = [int]$probe.streams[0].height
        source_fps = $probe.streams[0].avg_frame_rate
        review_fps = 2
        expected_frames = $expectedFrames
        extracted_frames = $frameFiles.Count
        sheets = (Get-ChildItem $sheetDir -Filter "sheet-*.jpg").Count
    }
}

[IO.File]::WriteAllText((Join-Path $reviewRoot "manifest.json"), ($manifest | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Output "Wrote 2fps source review to $reviewRoot"
