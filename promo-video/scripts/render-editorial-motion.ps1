param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$python = "C:\Users\gqy17\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
$renderer = Join-Path $PSScriptRoot "render_editorial_motion.py"
$opening = Join-Path $projectDir "01-source/generated/opening-hangzhou-dawn-v001.png"
$frog = Join-Path $workspaceDir "mobile/assets/species/pelophylax_nigromaculatus.webp"
$insect = Join-Path $workspaceDir "mobile/assets/species/cryptotympana_atrata.webp"
$motionDir = Join-Path $projectDir "05-motion/editorial"
$posterDir = Join-Path $projectDir "09-qc/frame-grabs"
New-Item -ItemType Directory -Force -Path $motionDir,$posterDir | Out-Null

$jobs = @(
    @{ Scene="opening"; Duration=7; Output="opening-sound-mystery-v001.mp4"; Poster="opening-sound-mystery-v001.jpg"; Source=$opening },
    @{ Scene="montage"; Duration=7; Output="multi-sound-montage-v011.mp4"; Poster="multi-sound-montage-v011.jpg"; Source=$opening },
    @{ Scene="technology"; Duration=6; Output="technology-evidence-v011.mp4"; Poster="technology-evidence-v011.jpg"; Source=$null },
    @{ Scene="tracks"; Duration=7; Output="three-track-merge-v001.mp4"; Poster="three-track-merge-v001.jpg"; Source=$null },
    @{ Scene="brand"; Duration=4; Output="brand-end-card-v011.mp4"; Poster="brand-end-card-v011.jpg"; Source=$null }
)

foreach ($job in $jobs) {
    $out = Join-Path $motionDir $job.Output
    $poster = Join-Path $posterDir $job.Poster
    if ((Test-Path -LiteralPath $out) -and -not $Force) {
        Write-Output "Skip existing motion scene: $($job.Scene)"
        continue
    }
    $arguments = @($renderer,"--scene",$job.Scene,"--duration",$job.Duration,"--output",$out,"--poster",$poster)
    if ($job.Source) { $arguments += @("--source",$job.Source) }
    if ($job.Scene -eq "montage") { $arguments += @("--frog",$frog,"--insect",$insect) }
    & $python @arguments
    if ($LASTEXITCODE -ne 0) { throw "Failed to render $($job.Scene)" }
    Write-Output "Wrote $out"
}
