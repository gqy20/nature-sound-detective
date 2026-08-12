param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$sourceDir = Join-Path $projectDir "01-source"
$proxyDir = Join-Path $projectDir "02-proxies/real-footage-v001"
$outputDir = Join-Path $projectDir "08-exports/segments/real-footage-v001"
$designDir = Join-Path $projectDir "04-design/real-footage-v001"
$softwareSource = Join-Path $projectDir "02-proxies/demo-v005/xykw-demo-flow-verified-30fps.mp4"
$overlay = Join-Path $designDir "real-footage-debug-overlay-1080p.png"
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$fontRegular = Join-Path $workspaceDir "mobile/assets/fonts/AlibabaPuHuiTi-Regular.otf"
$fontSemibold = Join-Path $workspaceDir "mobile/assets/fonts/AlibabaPuHuiTi-SemiBold.otf"

New-Item -ItemType Directory -Force -Path $proxyDir, $outputDir, $designDir | Out-Null

foreach ($required in @($softwareSource, $python, $fontRegular, $fontSemibold)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing required input: $required" }
}

& $python (Join-Path $PSScriptRoot "render-real-footage-debug-overlay.py") `
    $fontRegular $fontSemibold $overlay
if ($LASTEXITCODE -ne 0) { throw "Failed to render the editorial overlay" }

$clips = @(
    [pscustomobject]@{ Source = "wudong.mp4"; Stem = "wudong"; Start = 11.5; Duration = 4.0 },
    [pscustomobject]@{ Source = "21630a.mp4"; Stem = "21630a"; Start = 10.5; Duration = 3.5 },
    [pscustomobject]@{ Source = "bdc47.mp4"; Stem = "bdc47"; Start = 0.0; Duration = 3.0 }
)

$manifest = @()
foreach ($clip in $clips) {
    $source = Join-Path $sourceDir $clip.Source
    $proxy = Join-Path $proxyDir ("{0}-silent-1080p30.mp4" -f $clip.Stem)
    $output = Join-Path $outputDir ("real-observation-{0}-v001-1080p.mp4" -f $clip.Stem)
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing source: $source" }

    if ($Force -or -not (Test-Path -LiteralPath $proxy)) {
        & ffmpeg -hide_banner -loglevel error -y -i $source `
            -map 0:v:0 -an -vf "fps=30,scale=1920:1080:flags=lanczos,setsar=1,format=yuv420p" `
            -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 18 -b:v 0 `
            -color_primaries bt709 -color_trc bt709 -colorspace bt709 -movflags +faststart $proxy
        if ($LASTEXITCODE -ne 0) { throw "Failed to create silent proxy: $($clip.Source)" }
    }

    if ($Force -or -not (Test-Path -LiteralPath $output)) {
        $filter = @"
[0:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,scale=1220:686:force_original_aspect_ratio=increase:flags=lanczos,crop=1220:686,setsar=1[observation];
[1:v]fps=30,settb=1/30,setpts=PTS-STARTPTS,scale=-2:940:flags=lanczos,setsar=1[software];
[2:v][software]overlay=110:70:shortest=1[stage1];
[stage1][observation]overlay=625:187:shortest=1[stage2];
[stage2][3:v]overlay=0:0:shortest=1,format=yuv420p[v]
"@
        & ffmpeg -hide_banner -loglevel error -y `
            -ss $clip.Start -t $clip.Duration -i $proxy `
            -ss 4.5 -t $clip.Duration -i $softwareSource `
            -f lavfi -t $clip.Duration -i "color=c=#F3F0E7:s=1920x1080:r=30" `
            -loop 1 -framerate 30 -t $clip.Duration -i $overlay `
            -filter_complex $filter -map "[v]" -an -t $clip.Duration -r 30 `
            -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 18 -b:v 0 `
            -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
            -pix_fmt yuv420p -movflags +faststart $output
        if ($LASTEXITCODE -ne 0) { throw "Failed to render debug segment: $($clip.Stem)" }
    }

    $probe = & ffprobe -v error -show_entries format=duration -select_streams v:0 `
        -show_entries stream=width,height,avg_frame_rate,codec_name -of json -- $output | ConvertFrom-Json
    $audioCount = [int](& ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 -- $output | Measure-Object -Line).Lines
    $manifest += [pscustomobject]@{
        id = $clip.Stem
        original_source = $source
        original_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        silent_proxy = $proxy
        selected_start_seconds = $clip.Start
        selected_duration_seconds = $clip.Duration
        software_source = $softwareSource
        software_start_seconds = 4.5
        output = $output
        output_width = [int]$probe.streams[0].width
        output_height = [int]$probe.streams[0].height
        output_fps = $probe.streams[0].avg_frame_rate
        audio_streams = $audioCount
    }
}

[IO.File]::WriteAllText(
    (Join-Path $outputDir "manifest.json"),
    ($manifest | ConvertTo-Json -Depth 5),
    [Text.UTF8Encoding]::new($false)
)
Write-Output "Wrote silent proxies to $proxyDir"
Write-Output "Wrote standalone debug segments to $outputDir"
