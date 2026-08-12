param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$renderer = Join-Path $PSScriptRoot "render_editorial_motion.py"
$audio = Join-Path $projectDir "06-audio/mix/final-mix-v011.wav"
$part02 = Join-Path $workspaceDir "artifacts/xykw-part02-4k.mp4"
$opening = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-v001.png"
$bird = Join-Path $workspaceDir "mobile/assets/species/pycnonotus_sinensis.webp"
$frog = Join-Path $workspaceDir "mobile/assets/species/pelophylax_nigromaculatus.webp"
$insect = Join-Path $workspaceDir "mobile/assets/species/cryptotympana_atrata.webp"
$waterStill = Join-Path $projectDir "01-source/licensed/stream-of-waterfall-ckpixel-cc-by-sa-4.jpg"
$fontRegular = Join-Path $workspaceDir "mobile/assets/fonts/AlibabaPuHuiTi-Regular.otf"
$fontSemibold = Join-Path $workspaceDir "mobile/assets/fonts/AlibabaPuHuiTi-SemiBold.otf"
$designDir = Join-Path $projectDir "04-design/fixes-v015"
$rawDir = Join-Path $projectDir "05-motion/debug-v015"
$outputDir = Join-Path $projectDir "08-exports/segments/fixes-v015"
$leadOverlay = Join-Path $designDir "s08-lead-overlay.png"
$fieldOverlay = Join-Path $designDir "s08-field-overlay.png"

New-Item -ItemType Directory -Force -Path $designDir, $rawDir, $outputDir | Out-Null
foreach ($path in @($python,$renderer,$audio,$part02,$opening,$bird,$frog,$insect,$waterStill,$fontRegular,$fontSemibold)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required input: $path" }
}

& $python (Join-Path $PSScriptRoot "render_s08_sync_overlay.py") $fontRegular $fontSemibold lead $leadOverlay
if ($LASTEXITCODE -ne 0) { throw "Failed to render S08 lead overlay" }
& $python (Join-Path $PSScriptRoot "render_s08_sync_overlay.py") $fontRegular $fontSemibold field $fieldOverlay
if ($LASTEXITCODE -ne 0) { throw "Failed to render S08 field overlay" }

$s03Raw = Join-Path $rawDir "S03-five-sound-montage-v015-1080p-silent.mp4"
$s07Raw = Join-Path $rawDir "S07-human-readable-technology-v015-1080p-silent.mp4"
$s03 = Join-Path $outputDir "S03-five-sound-montage-v015-1080p.mp4"
$s07 = Join-Path $outputDir "S07-human-readable-technology-v015-1080p.mp4"
$s08 = Join-Path $outputDir "S08-field-check-sync-v015-1080p.mp4"

if ($Force -or -not (Test-Path -LiteralPath $s03Raw)) {
    & $python $renderer --scene montage --duration 7 --width 1920 --height 1080 --encoder h264_nvenc `
        --source $opening --bird $bird --frog $frog --insect $insect --water $waterStill --weather $opening `
        --output $s03Raw
    if ($LASTEXITCODE -ne 0) { throw "Failed to render revised S03" }
}

if ($Force -or -not (Test-Path -LiteralPath $s07Raw)) {
    & $python $renderer --scene technology --duration 6 --width 1920 --height 1080 --encoder h264_nvenc `
        --output $s07Raw
    if ($LASTEXITCODE -ne 0) { throw "Failed to render revised S07" }
}

if ($Force -or -not (Test-Path -LiteralPath $s03)) {
    & ffmpeg -hide_banner -loglevel error -y -i $s03Raw -ss 11 -t 7 -i $audio `
        -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t 7 -movflags +faststart $s03
    if ($LASTEXITCODE -ne 0) { throw "Failed to add synchronized audio to S03" }
}

if ($Force -or -not (Test-Path -LiteralPath $s07)) {
    & ffmpeg -hide_banner -loglevel error -y -i $s07Raw -ss 41 -t 6 -i $audio `
        -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t 6 -movflags +faststart $s07
    if ($LASTEXITCODE -ne 0) { throw "Failed to add synchronized audio to S07" }
}

if ($Force -or -not (Test-Path -LiteralPath $s08)) {
    $filter = @"
[0:v]fps=30,trim=duration=2.15,settb=1/30,setpts=PTS-STARTPTS[a];
[1:v]fps=30,trim=duration=2.85,settb=1/30,setpts=PTS-STARTPTS[b];
[2:v]fps=30,trim=duration=6.0,settb=1/30,setpts=PTS-STARTPTS[c];
[a][b][c]concat=n=3:v=1:a=0[ui];
[ui]split=2[phone0][detail0];
[phone0]scale=-2:940:flags=lanczos,setsar=1[phone];
[detail0]crop=1560:900:300:2200,scale=960:554:flags=lanczos,setsar=1,format=rgba,fade=t=in:st=5:d=0.18:alpha=1[detail];
[3:v][phone]overlay=170:70:shortest=1[stage1];
[stage1][4:v]overlay=0:0:enable='lt(t,5)':shortest=1[stage2];
[stage2][detail]overlay=875:255:enable='gte(t,5)':shortest=1[stage3];
[stage3][5:v]overlay=0:0:enable='gte(t,5)':shortest=1,format=yuv420p[v]
"@
    & ffmpeg -hide_banner -loglevel error -y `
        -ss 8 -t 2.15 -i $part02 `
        -ss 16 -t 2.85 -i $part02 `
        -ss 54 -t 6 -i $part02 `
        -f lavfi -t 11 -i "color=c=#F3F0E7:s=1920x1080:r=30" `
        -loop 1 -framerate 30 -t 11 -i $leadOverlay `
        -loop 1 -framerate 30 -t 11 -i $fieldOverlay `
        -ss 47 -t 11 -i $audio `
        -filter_complex $filter -map "[v]" -map 6:a:0 -t 11 -r 30 `
        -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 18 -b:v 0 -pix_fmt yuv420p `
        -c:a aac -b:a 192k -ar 48000 -colorspace bt709 -color_primaries bt709 -color_trc bt709 `
        -movflags +faststart $s08
    if ($LASTEXITCODE -ne 0) { throw "Failed to render synchronized S08" }
}

$outputs = @(
    [pscustomobject]@{ id="S03"; file=$s03; global_start=11.0; duration=7.0; review_note="Five named sound categories each use a distinct matching visual." },
    [pscustomobject]@{ id="S07"; file=$s07; global_start=41.0; duration=6.0; review_note="Audience-facing three-step explanation; child confirmation is centre-anchored." },
    [pscustomobject]@{ id="S08"; file=$s08; global_start=47.0; duration=11.0; review_note="Normal-speed source cuts; field-check controls begin at local 5.0s, immediately before the 5.196s narration cue." }
)
foreach ($item in $outputs) {
    $probe = & ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $item.file | ConvertFrom-Json
    $item | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $item.file -Algorithm SHA256).Hash
    $item | Add-Member -NotePropertyName probe -NotePropertyValue $probe
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"),($outputs | ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote feedback-fix segments to $outputDir"
