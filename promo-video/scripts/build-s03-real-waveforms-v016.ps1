param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$renderer = Join-Path $PSScriptRoot "render_editorial_motion.py"
$preparer = Join-Path $PSScriptRoot "prepare_s03_real_audio.py"
$masterMix = Join-Path $projectDir "06-audio/mix/final-mix-v011.wav"

$birdAudio = Join-Path $projectDir "01-source/wudong.mp4"
$frogAudio = Join-Path $workspaceDir "data/raw/inaturalist/other_frog/inat_377806290_2055090.m4a"
$insectAudio = Join-Path $workspaceDir "data/raw/inaturalist/cryptotympana_atrata/inat_125124891_493119.m4a"
$waterAudio = Join-Path $projectDir "01-source/licensed/flowing-water-100019.ogg"
$windAudio = Join-Path $workspaceDir "data/raw/freesound/previews/wind_trees/freesound_276294.mp3"
$rainAudio = Join-Path $workspaceDir "data/raw/freesound/previews/rain_water_park/freesound_200972.mp3"

$opening = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-v001.png"
$birdStill = Join-Path $projectDir "04-design/fixes-v016/s03-bird-field-frame.png"
$weatherStill = Join-Path $projectDir "04-design/fixes-v016/s03-weather-field-frame.png"
$frogStill = Join-Path $workspaceDir "mobile/assets/species/pelophylax_nigromaculatus.webp"
$insectStill = Join-Path $workspaceDir "mobile/assets/species/cryptotympana_atrata.webp"
$waterStill = Join-Path $projectDir "01-source/licensed/stream-of-waterfall-ckpixel-cc-by-sa-4.jpg"

$designDir = Join-Path $projectDir "04-design/fixes-v016"
$audioDir = Join-Path $projectDir "06-audio/nature-stems/s03-v016"
$rawDir = Join-Path $projectDir "05-motion/debug-v016"
$outputDir = Join-Path $projectDir "08-exports/segments/fixes-v016"
$reviewDir = Join-Path $projectDir "09-qc/s03-real-waveforms-v016-2fps"

New-Item -ItemType Directory -Force -Path $designDir,$audioDir,$rawDir,$outputDir,$reviewDir | Out-Null
foreach ($path in @($python,$renderer,$preparer,$masterMix,$birdAudio,$frogAudio,$insectAudio,$waterAudio,$windAudio,$rainAudio,$opening,$frogStill,$insectStill,$waterStill)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required input: $path" }
}

if ($Force -or -not (Test-Path -LiteralPath $birdStill)) {
    & ffmpeg -hide_banner -loglevel error -y -ss 11.5 -i $birdAudio -frames:v 1 $birdStill
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract bird field frame" }
}
if ($Force -or -not (Test-Path -LiteralPath $weatherStill)) {
    & ffmpeg -hide_banner -loglevel error -y -ss 10.5 -i (Join-Path $projectDir "01-source/21630a.mp4") -frames:v 1 $weatherStill
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract weather field frame" }
}

$waveforms = Join-Path $audioDir "s03-waveforms-v016.json"
$natureBed = Join-Path $audioDir "s03-category-nature-bed-v016.wav"
if ($Force -or -not (Test-Path -LiteralPath $waveforms) -or -not (Test-Path -LiteralPath $natureBed)) {
    & $python $preparer --bird $birdAudio --frog $frogAudio --insect $insectAudio --water $waterAudio --wind $windAudio --rain $rainAudio --output-dir $audioDir
    if ($LASTEXITCODE -ne 0) { throw "Failed to prepare S03 category audio" }
}

$silent = Join-Path $rawDir "S03-real-audio-waveforms-v016-1080p-silent.mp4"
$output = Join-Path $outputDir "S03-real-audio-waveforms-v016-1080p.mp4"
if ($Force -or -not (Test-Path -LiteralPath $silent)) {
    & $python $renderer --scene montage --duration 7 --width 1920 --height 1080 --encoder h264_nvenc `
        --source $opening --bird $birdStill --frog $frogStill --insect $insectStill --water $waterStill --weather $weatherStill `
        --waveforms $waveforms --output $silent
    if ($LASTEXITCODE -ne 0) { throw "Failed to render sample-derived S03 waveforms" }
}

if ($Force -or -not (Test-Path -LiteralPath $output)) {
    $mix = "[1:a]volume=1.0[program];[2:a]volume=0.34[nature];[program][nature]amix=inputs=2:duration=first:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=7,aresample=48000[a]"
    & ffmpeg -hide_banner -loglevel error -y -i $silent -ss 11 -t 7 -i $masterMix -i $natureBed `
        -filter_complex $mix -map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 256k -ar 48000 -t 7 -movflags +faststart $output
    if ($LASTEXITCODE -ne 0) { throw "Failed to mix real category sound into S03" }
}

Get-ChildItem -LiteralPath $reviewDir -Filter '*.png' -File | Remove-Item -Force
& ffmpeg -hide_banner -loglevel error -y -i $output -vf "fps=2,scale=960:-2:flags=lanczos" -q:v 2 (Join-Path $reviewDir "frame-%03d.png")
if ($LASTEXITCODE -ne 0) { throw "Failed to extract 2 fps review frames" }

$waveformManifest = Get-Content -LiteralPath $waveforms -Raw -Encoding UTF8 | ConvertFrom-Json
$probe = & ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $output | ConvertFrom-Json
$manifest = [ordered]@{
    id = "S03"
    file = $output
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    probe = $probe
    review_fps = 2
    review_frames = (Get-ChildItem -LiteralPath $reviewDir -Filter '*.png' -File).Count
    waveform_truth = "Each displayed category trace is sampled from the exact PCM clip in the nature bed. Narration and music are excluded from trace generation."
    audio_sources = $waveformManifest.categories
    licenses = @(
        [ordered]@{ label="bird"; license="user-provided field recording"; source=$birdAudio },
        [ordered]@{ label="frog"; license="CC0"; source_page="https://www.inaturalist.org/observations/377806290" },
        [ordered]@{ label="insect"; license="CC BY"; attribution="Yi CHEN"; source_page="https://www.inaturalist.org/observations/125124891" },
        [ordered]@{ label="flowing_water"; license="public domain"; attribution="Fg2"; source_page="https://commons.wikimedia.org/wiki/File:Flowing-water-100019.ogg" },
        [ordered]@{ label="wind"; license="CC0"; attribution="Sandermotions / Freesound 276294" },
        [ordered]@{ label="rain"; license="CC0"; attribution="NHumphrey / Freesound 200972" }
    )
}
[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"),($manifest | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote $output"
Write-Output "Wrote 2 fps review frames to $reviewDir"
