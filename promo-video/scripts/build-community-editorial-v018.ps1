param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$renderer = Join-Path $PSScriptRoot "render_community_narrative.py"
$assistRenderer = Join-Path $PSScriptRoot "render_community_assist_screen.py"
$screenshot = Join-Path $workspaceDir "artifacts/recording-part05-map.png"
$audio = Join-Path $projectDir "06-audio/mix/final-mix-v011.wav"
$designDir = Join-Path $projectDir "04-design/fixes-v018"
$rawDir = Join-Path $projectDir "05-motion/debug-v018"
$outputDir = Join-Path $projectDir "08-exports/segments/fixes-v018"
$reviewDir = Join-Path $projectDir "09-qc/community-editorial-v018-2fps"
$assistScreen = Join-Path $designDir "community-assist-screen-v018.png"
New-Item -ItemType Directory -Force -Path $designDir,$rawDir,$outputDir,$reviewDir | Out-Null

foreach ($path in @($python,$renderer,$assistRenderer,$screenshot,$audio)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required input: $path" }
}

if ($Force -or -not (Test-Path -LiteralPath $assistScreen)) {
    & $python $assistRenderer $screenshot $assistScreen
    if ($LASTEXITCODE -ne 0) { throw "Failed to prepare assist state" }
}

$jobs = @(
    [pscustomobject]@{ id="S11"; scene="today_editorial"; source=$screenshot; start=72; duration=9; stem="S11-editorial-sound-timeline-v018" },
    [pscustomobject]@{ id="S12"; scene="assist_editorial"; source=$assistScreen; start=81; duration=10; stem="S12-editorial-listening-relay-v018" }
)

foreach ($job in $jobs) {
    $silent = Join-Path $rawDir ($job.stem + "-1080p-silent.mp4")
    $output = Join-Path $outputDir ($job.stem + "-1080p.mp4")
    if ($Force -or -not (Test-Path -LiteralPath $silent)) {
        & $python $renderer --scene $job.scene --source $job.source --output $silent --duration $job.duration --encoder h264_nvenc
        if ($LASTEXITCODE -ne 0) { throw "Failed to render $($job.id)" }
    }
    if ($Force -or -not (Test-Path -LiteralPath $output)) {
        & ffmpeg -hide_banner -loglevel error -y -i $silent -ss $job.start -t $job.duration -i $audio `
            -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t $job.duration -movflags +faststart $output
        if ($LASTEXITCODE -ne 0) { throw "Failed to add synchronized audio to $($job.id)" }
    }
    $sceneReview = Join-Path $reviewDir $job.id
    New-Item -ItemType Directory -Force -Path $sceneReview | Out-Null
    Get-ChildItem -LiteralPath $sceneReview -Filter '*.png' -File | Remove-Item -Force
    & ffmpeg -hide_banner -loglevel error -y -i $output -vf "fps=2,scale=960:-2:flags=lanczos" -q:v 2 (Join-Path $sceneReview "frame-%03d.png")
    if ($LASTEXITCODE -ne 0) { throw "Failed 2 fps review extraction for $($job.id)" }
    $job | Add-Member -NotePropertyName output -NotePropertyValue $output
    $job | Add-Member -NotePropertyName sha256 -NotePropertyValue (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $job | Add-Member -NotePropertyName review_frames -NotePropertyValue (Get-ChildItem -LiteralPath $sceneReview -Filter '*.png' -File).Count
    $probe = & ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $output | ConvertFrom-Json
    $job | Add-Member -NotePropertyName probe -NotePropertyValue $probe
}

[IO.File]::WriteAllText((Join-Path $outputDir "manifest.json"),($jobs | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output "Wrote editorial community debug segments to $outputDir"
