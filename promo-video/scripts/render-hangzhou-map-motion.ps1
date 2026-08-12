param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$source = Join-Path $workspaceDir "mobile/assets/maps/hangzhou_osm.png"
$output = Join-Path $projectDir "05-motion/hangzhou-map/hangzhou-soundscape-map-v005.mp4"
$poster = Join-Path $projectDir "09-qc/frame-grabs/hangzhou-soundscape-map-v005.jpg"
$renderer = Join-Path $PSScriptRoot "render_hangzhou_map_motion.py"

foreach ($required in @($python, $source, $renderer)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Missing renderer dependency: $required" }
}
if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Skip existing map animation: $output"
    exit 0
}
& $python $renderer --source $source --output $output --poster $poster --duration 25 --fps 30
if ($LASTEXITCODE -ne 0) { throw "Failed to render Hangzhou map animation" }
Write-Output "Wrote $output"
Write-Output "Wrote $poster"
