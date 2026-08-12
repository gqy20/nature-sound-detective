param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$audioPath = Join-Path $workspaceDir "artifacts/xykw-original-sound.wav"
$waveformPath = Join-Path $projectDir "05-motion/waveforms/original-sound-waveform-4k.png"
$spectrumPath = Join-Path $projectDir "05-motion/spectrogram/original-sound-spectrum-4k.png"

foreach ($required in @($audioPath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Missing source asset: $required"
    }
}

if ($Force -or -not (Test-Path -LiteralPath $waveformPath)) {
    Write-Output "Rendering waveform"
    & ffmpeg -hide_banner -loglevel error -y -i $audioPath -filter_complex "aformat=channel_layouts=mono,showwavespic=s=3200x600:colors=0x185640" -frames:v 1 $waveformPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to render waveform" }
}

if ($Force -or -not (Test-Path -LiteralPath $spectrumPath)) {
    Write-Output "Rendering spectrogram"
    & ffmpeg -hide_banner -loglevel error -y -i $audioPath -lavfi "showspectrumpic=s=3200x900:legend=0:color=viridis:scale=sqrt" -frames:v 1 $spectrumPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to render spectrogram" }
}

Write-Output $waveformPath
Write-Output $spectrumPath
