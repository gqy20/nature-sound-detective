param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$segmentDir = Join-Path $projectDir "08-exports/segments/real-footage-v001"
$reviewRoot = Join-Path $projectDir "09-qc/segment-review-2fps-v001"
New-Item -ItemType Directory -Force -Path $reviewRoot | Out-Null

$manifest = @()
$segments = Get-ChildItem -LiteralPath $segmentDir -Filter "real-observation-*-1080p.mp4" | Sort-Object Name
if ($segments.Count -eq 0) { throw "No debug segments found in $segmentDir" }

foreach ($segment in $segments) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($segment.Name)
    $clipDir = Join-Path $reviewRoot $stem
    $frameDir = Join-Path $clipDir "frames"
    $sheetDir = Join-Path $clipDir "sheets"
    New-Item -ItemType Directory -Force -Path $frameDir, $sheetDir | Out-Null

    if ($Force) {
        Get-ChildItem -LiteralPath $frameDir -Filter "frame-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem -LiteralPath $sheetDir -Filter "sheet-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    if (-not (Get-ChildItem -LiteralPath $frameDir -Filter "frame-*.jpg" -ErrorAction SilentlyContinue)) {
        & ffmpeg -hide_banner -loglevel error -y -i $segment.FullName `
            -vf "fps=2:start_time=0,scale=960:540:flags=lanczos" `
            -q:v 2 -start_number 0 (Join-Path $frameDir "frame-%04d.jpg")
        if ($LASTEXITCODE -ne 0) { throw "Failed 2fps extraction: $($segment.Name)" }
    }

    if (-not (Get-ChildItem -LiteralPath $sheetDir -Filter "sheet-*.jpg" -ErrorAction SilentlyContinue)) {
        & ffmpeg -hide_banner -loglevel error -y -i $segment.FullName `
            -vf "fps=2:start_time=0,scale=960:540:flags=lanczos,tile=4x2:nb_frames=8:padding=10:margin=12:color=0x171A18" `
            -q:v 2 -vsync 0 -start_number 1 (Join-Path $sheetDir "sheet-%02d.jpg")
        if ($LASTEXITCODE -ne 0) { throw "Failed 2fps contact sheet: $($segment.Name)" }
    }

    $probe = & ffprobe -v error -show_entries format=duration -select_streams v:0 `
        -show_entries stream=width,height,avg_frame_rate -of json -- $segment.FullName | ConvertFrom-Json
    $frames = Get-ChildItem -LiteralPath $frameDir -Filter "frame-*.jpg" | Sort-Object Name
    $manifest += [pscustomobject]@{
        segment = $segment.FullName
        duration_seconds = [double]$probe.format.duration
        width = [int]$probe.streams[0].width
        height = [int]$probe.streams[0].height
        fps = $probe.streams[0].avg_frame_rate
        review_fps = 2
        extracted_frames = $frames.Count
        sheets = (Get-ChildItem -LiteralPath $sheetDir -Filter "sheet-*.jpg").Count
    }
}

[IO.File]::WriteAllText(
    (Join-Path $reviewRoot "manifest.json"),
    ($manifest | ConvertTo-Json -Depth 4),
    [Text.UTF8Encoding]::new($false)
)
Write-Output "Wrote 2fps segment review to $reviewRoot"
