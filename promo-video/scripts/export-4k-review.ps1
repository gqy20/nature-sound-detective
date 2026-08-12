param(
    [string]$Version = "v011",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectDir ("08-exports/review/xykw-promo-polish-{0}-clean.mp4" -f $Version)
$subtitles = Join-Path $projectDir ("07-edit/subtitles/xykw-promo-designed-{0}.ass" -f $Version)
$outputDir = Join-Path $projectDir "08-exports/4k"
$output = Join-Path $outputDir ("xykw-promo-polish-{0}-4k.mp4" -f $Version)
$manifestPath = Join-Path $outputDir ("xykw-promo-polish-{0}-4k-manifest.json" -f $Version)
$fonts = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

if (-not (Test-Path -LiteralPath $source)) { throw "Missing clean source: $source" }
if (-not (Test-Path -LiteralPath $subtitles)) { throw "Missing subtitles: $subtitles" }

if (-not (Test-Path -LiteralPath $output) -or $Force) {
    $escapedAss = $subtitles.Replace('\','/').Replace(':','\:')
    $escapedFonts = $fonts.Replace('\','/').Replace(':','\:')
    $filter = "scale=3840:2160:flags=lanczos,ass='$escapedAss':fontsdir='$escapedFonts'"
    & ffmpeg -hide_banner -loglevel error -y -i $source `
        -vf $filter `
        -map 0:v:0 -map 0:a:0 `
        -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 18 -b:v 0 `
        -profile:v high -pix_fmt yuv420p -r 30 `
        -colorspace bt709 -color_primaries bt709 -color_trc bt709 `
        -c:a copy -movflags +faststart $output
    if ($LASTEXITCODE -ne 0) { throw "Failed to export 4K review master" }
}

$probe = & ffprobe -v error -show_entries format=duration,size:stream=codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels -of json $output | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
$manifest = [pscustomobject]@{
    version = $Version
    output = $output
    source = $source
    subtitles = $subtitles
    width = 3840
    height = 2160
    fps = 30
    upscale_filter = "Lanczos"
    subtitle_render = "ASS rendered on 3840x2160 canvas"
    video_encoder = "h264_nvenc"
    quality = "CQ 18, preset p7, HQ tune"
    audio = "copied from v011 clean master"
    duration = [double]$probe.format.duration
    size_bytes = [long]$probe.format.size
    sha256 = $hash
    generated_at = (Get-Date).ToString("o")
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $output"
Write-Output "Wrote $manifestPath"
