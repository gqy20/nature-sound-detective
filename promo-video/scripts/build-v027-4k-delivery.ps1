param(
    [string]$Version = "v027",
    [string]$Encoder = "h264_nvenc",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectDir "08-exports/1080p/xykw-promo-$Version-1080p.mp4"
$outputDir = Join-Path $projectDir "08-exports/4k"
$output = Join-Path $outputDir "xykw-promo-$Version-4k.mp4"
$manifestPath = Join-Path $outputDir "xykw-promo-$Version-4k-manifest.json"
$provenancePath = Join-Path $outputDir "xykw-promo-$Version-4k-provenance.md"
$reviewDir = Join-Path $projectDir "09-qc/$Version-master-4k-1fps"
New-Item -ItemType Directory -Force -Path $outputDir, $reviewDir | Out-Null

if (-not (Test-Path -LiteralPath $source)) { throw "Missing 1080p $Version master: $source" }

if ($Force -or -not (Test-Path -LiteralPath $output)) {
    $filter = "scale=3840:2160:flags=lanczos+accurate_rnd+full_chroma_int,setsar=1,fps=30,format=yuv420p"
    $codec = if ($Encoder -eq "h264_nvenc") {
        @("-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "15", "-b:v", "0")
    } else {
        @("-c:v", "libx264", "-preset", "slow", "-crf", "16")
    }
    $arguments = @(
        "-hide_banner", "-loglevel", "error", "-y",
        "-i", $source,
        "-vf", $filter,
        "-map", "0:v:0", "-map", "0:a:0"
    )
    $arguments += $codec
    $arguments += @(
        "-pix_fmt", "yuv420p",
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
        "-c:a", "copy", "-movflags", "+faststart", $output
    )
    & ffmpeg @arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed to build $Version 4K delivery master" }
}

Get-ChildItem -LiteralPath $reviewDir -Filter "frame-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force
& ffmpeg -hide_banner -loglevel error -y -i $output -vf "fps=1,scale=960:540:flags=lanczos" -q:v 2 -start_number 0 (Join-Path $reviewDir "frame-%03d.jpg")
if ($LASTEXITCODE -ne 0) { throw "Failed 4K review extraction" }

$probe = & ffprobe -v error -show_entries format=duration,size,bit_rate:stream=codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels,color_space,color_transfer,color_primaries -of json -- $output | ConvertFrom-Json
$manifest = [pscustomobject]@{
    version = $Version
    output = $output
    source = $source
    export_kind = "4K delivery upscale from approved $Version 1080p master"
    scaler = "FFmpeg Lanczos accurate_rnd full_chroma_int"
    width = 3840
    height = 2160
    fps = 30
    duration = [double]$probe.format.duration
    size_bytes = [long]$probe.format.size
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    source_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    review_frames = (Get-ChildItem -LiteralPath $reviewDir -Filter "frame-*.jpg").Count
    probe = $probe
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))

$provenance = @(
    "# $Version 4K delivery provenance",
    "",
    "- Content source: approved xykw-promo-$Version-1080p.mp4.",
    "- Output: 3840x2160, 30 fps, BT.709, H.264, original standardized AAC audio.",
    "- Scaling: Lanczos accurate rounding with full chroma interpolation.",
    "- This is a high-quality 4K delivery upscale, not a native 4K re-render of every $Version design layer.",
    "- Review: one frame per second extracted after export."
) -join [Environment]::NewLine
[IO.File]::WriteAllText($provenancePath, $provenance, [Text.UTF8Encoding]::new($false))

Write-Output "Wrote $output"
Write-Output "Wrote $manifestPath"
Write-Output "Wrote $provenancePath"
