param([switch]$Force, [string]$Version = "v001")

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$voice = Join-Path $projectDir ("06-audio/voiceover/formal/formal-voiceover-{0}.wav" -f $Version)
$music = Join-Path $workspaceDir "artifacts/xykw-generated-music.mp3"
$natural = Join-Path $workspaceDir "artifacts/xykw-original-sound.wav"
$output = Join-Path $projectDir ("06-audio/mix/final-mix-{0}.wav" -f $Version)
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$masterDuration = [double]$config.master.duration
$musicFadeOut = [math]::Max(0, $masterDuration - 5)
$postcardStart = [double](($config.scenes | Where-Object { $_.id -eq "S14" } | Select-Object -First 1).start)
$masterDurationText = $masterDuration.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
$musicFadeOutText = $musicFadeOut.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
$postcardDelayMs = [math]::Round($postcardStart * 1000)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null

if ((Test-Path -LiteralPath $output) -and -not $Force) {
    Write-Output "Skip existing final mix: $output"
    exit 0
}

$filter = @"
[0:a]apad=whole_dur=$masterDurationText,atrim=0:$masterDurationText,asetpts=PTS-STARTPTS[voice];
[1:a]atrim=0:$masterDurationText,asetpts=PTS-STARTPTS,volume=0.13,afade=t=in:st=0:d=3,afade=t=out:st=${musicFadeOutText}:d=5[music];
[music][voice]sidechaincompress=threshold=0.018:ratio=7:attack=25:release=420[ducked];
[2:a]atrim=0:7,asetpts=PTS-STARTPTS,volume=0.22,afade=t=in:st=0:d=0.4,afade=t=out:st=6.2:d=0.8[nat1];
[2:a]atrim=18:51,asetpts=PTS-STARTPTS,volume=0.095,afade=t=in:st=0:d=1,afade=t=out:st=31:d=2,adelay=7000|7000[nat2];
[2:a]atrim=72:78,asetpts=PTS-STARTPTS,volume=0.18,afade=t=in:st=0:d=0.8,afade=t=out:st=5:d=1,adelay=$postcardDelayMs|$postcardDelayMs[nat3];
[ducked][voice][nat1][nat2][nat3]amix=inputs=5:duration=longest:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=9,atrim=0:$masterDurationText[out]
"@

& ffmpeg -hide_banner -loglevel error -y -i $voice -i $music -i $natural -filter_complex $filter -map "[out]" -ar 48000 -ac 2 -c:a pcm_s24le $output
if ($LASTEXITCODE -ne 0) { throw "Failed to create final audio mix" }
Write-Output "Wrote $output"
