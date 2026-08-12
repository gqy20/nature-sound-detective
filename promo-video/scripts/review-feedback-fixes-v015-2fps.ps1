param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$segmentDir = Join-Path $projectDir "08-exports/segments/fixes-v015"
$reviewDir = Join-Path $projectDir "09-qc/fixes-v015-2fps"
New-Item -ItemType Directory -Force -Path $reviewDir | Out-Null

$manifest = @()
$segments = Get-ChildItem -LiteralPath $segmentDir -Filter "S*.mp4" | Sort-Object Name
foreach ($segment in $segments) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($segment.Name)
    $frameDir = Join-Path $reviewDir "$stem/frames"
    $sheetDir = Join-Path $reviewDir "$stem/sheets"
    New-Item -ItemType Directory -Force -Path $frameDir, $sheetDir | Out-Null
    if ($Force) {
        Get-ChildItem -LiteralPath $frameDir -Filter "*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem -LiteralPath $sheetDir -Filter "*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
    & ffmpeg -hide_banner -loglevel error -y -i $segment.FullName `
        -vf "fps=2:start_time=0,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 `
        (Join-Path $frameDir "frame-%04d.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed 2fps extraction for $($segment.Name)" }
    & ffmpeg -hide_banner -loglevel error -y -i $segment.FullName `
        -vf "fps=2:start_time=0,scale=960:540:flags=lanczos,tile=4x4:nb_frames=16:padding=8:margin=12:color=0x171A18" `
        -q:v 2 -vsync 0 -start_number 1 (Join-Path $sheetDir "sheet-%02d.jpg")
    if ($LASTEXITCODE -ne 0) { throw "Failed contact sheet for $($segment.Name)" }

    $probe = & ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $segment.FullName | ConvertFrom-Json
    $manifest += [pscustomobject]@{
        file = $segment.FullName
        duration = [double]$probe.format.duration
        review_fps = 2
        extracted_frames = (Get-ChildItem -LiteralPath $frameDir -Filter "*.jpg").Count
        sheets = (Get-ChildItem -LiteralPath $sheetDir -Filter "*.jpg").Count
        streams = $probe.streams
    }
}
[IO.File]::WriteAllText((Join-Path $reviewDir "manifest.json"),($manifest | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote 2fps review to $reviewDir"
