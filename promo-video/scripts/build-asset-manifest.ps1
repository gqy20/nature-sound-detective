param(
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $projectDir "video-config.json"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir $config.sourceRoot))
$names = $config.scenes | Where-Object { $_.mode -eq "source" } | Select-Object -ExpandProperty source -Unique
$rows = @()

foreach ($name in $names) {
    $path = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing source asset: $path"
    }
    $probeRaw = & ffprobe -v error -show_entries "format=duration,size:stream=index,codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels" -of json -- $path
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe failed for $path"
    }
    $probe = $probeRaw | ConvertFrom-Json
    $video = $probe.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1
    $audio = $probe.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    $usedBy = ($config.scenes | Where-Object { $_.source -eq $name } | Select-Object -ExpandProperty id) -join ";"
    $relativePath = $path
    $workspacePrefix = $workspaceDir.TrimEnd("\") + "\"
    if ($path.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $path.Substring($workspacePrefix.Length)
    }
    $rows += [pscustomobject]@{
        file = $name
        path = $relativePath.Replace("\", "/")
        duration_seconds = [math]::Round([double]$probe.format.duration, 3)
        size_bytes = [int64]$probe.format.size
        video_codec = $video.codec_name
        width = $video.width
        height = $video.height
        frame_rate = $video.r_frame_rate
        audio_codec = if ($audio) { $audio.codec_name } else { "none" }
        sample_rate = if ($audio) { $audio.sample_rate } else { "" }
        channels = if ($audio) { $audio.channels } else { "" }
        used_by = $usedBy
        sha256 = $hash.Hash.ToLowerInvariant()
    }
}

$csvPath = Join-Path $projectDir "asset-manifest.csv"
$jsonPath = Join-Path $projectDir "asset-manifest.json"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
Write-Output "Wrote $csvPath"
Write-Output "Wrote $jsonPath"
