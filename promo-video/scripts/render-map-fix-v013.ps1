param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$outputDir = Join-Path $projectDir "05-motion/4k-v013"
$posterDir = Join-Path $projectDir "09-qc/frame-grabs/v013-map-fix"
$output = Join-Path $outputDir "hangzhou-soundscape-map-v013-4k.mp4"
$poster = Join-Path $posterDir "hangzhou-map-v013-4k.jpg"
New-Item -ItemType Directory -Force -Path $outputDir, $posterDir | Out-Null

if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Keep existing fixed map: $output"
    exit 0
}

& $python (Join-Path $PSScriptRoot "render_hangzhou_map_motion.py") `
    --source (Join-Path $workspaceDir "mobile/assets/maps/hangzhou_osm.png") `
    --output $output `
    --poster $poster `
    --duration 25 `
    --fps 30 `
    --width 3840 `
    --height 2160 `
    --encoder h264_nvenc
if ($LASTEXITCODE -ne 0) { throw "Failed to render fixed native 4K Hangzhou map" }

Write-Output "Wrote $output"
