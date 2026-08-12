param([string]$Version = "v004")

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $projectDir "video-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$sceneDir = Join-Path $projectDir "07-edit/scene-renders"
$exportDir = Join-Path $projectDir "08-exports/review"
$rough = Join-Path $exportDir ("xykw-promo-rough-{0}.mp4" -f $Version)
$clean = Join-Path $exportDir ("xykw-promo-polish-{0}-clean.mp4" -f $Version)
$final = Join-Path $exportDir ("xykw-promo-polish-{0}.mp4" -f $Version)
$versionAudio = Join-Path $projectDir ("06-audio/mix/final-mix-{0}.wav" -f $Version)
$audioName = if (Test-Path -LiteralPath $versionAudio) { "final-mix-{0}.wav" -f $Version } else { "final-mix-v001.wav" }
$audio = Join-Path $projectDir ("06-audio/mix/{0}" -f $audioName)
$versionSubtitle = Join-Path $projectDir ("07-edit/subtitles/xykw-promo-designed-{0}.ass" -f $Version)
$subtitleName = if (Test-Path -LiteralPath $versionSubtitle) { "xykw-promo-designed-{0}.ass" -f $Version } else { "xykw-promo-designed-v004.ass" }
$subtitles = Join-Path $projectDir ("07-edit/subtitles/{0}" -f $subtitleName)
$fonts = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts"
$masterDuration = [double]$config.master.duration
$masterDurationText = $masterDuration.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
New-Item -ItemType Directory -Force -Path $exportDir | Out-Null

$ffargs = @("-hide_banner", "-loglevel", "error", "-y")
$filters = @()
for ($i = 0; $i -lt $config.scenes.Count; $i++) {
    $scene = $config.scenes[$i]
    $safeTitle = $scene.title -replace '[\\/:*?"<>|]', '_'
    $path = Join-Path $sceneDir ("{0}-{1}.mp4" -f $scene.id, $safeTitle)
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing scene render: $path" }
    $ffargs += @("-i", $path)
    $duration = [double]$scene.end - [double]$scene.start
    $chain = "[$($i):v]fps=30,settb=expr=1/30,setpts=PTS-STARTPTS"
    if ($i -gt 0) { $chain += ",fade=t=in:st=0:d=0.12:color=0xF3F0E7" }
    if ($i -lt $config.scenes.Count - 1) {
        $fadeStart = ($duration - 0.12).ToString('0.00',[Globalization.CultureInfo]::InvariantCulture)
        $chain += ",fade=t=out:st=$fadeStart`:d=0.12:color=0xF3F0E7"
    }
    $filters += "$chain[v$i]"
}
$concatInputs = (0..($config.scenes.Count - 1) | ForEach-Object { "[v$_]" }) -join ""
$filters += "${concatInputs}concat=n=$($config.scenes.Count):v=1:a=0,trim=duration=$masterDurationText,setpts=PTS-STARTPTS,format=yuv420p[outv]"
$ffargs += @("-filter_complex", ($filters -join ";"), "-map", "[outv]", "-an", "-r", "30", "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-movflags", "+faststart", $rough)
& ffmpeg @ffargs
if ($LASTEXITCODE -ne 0) { throw "Failed to build transitioned v004 master" }

& ffmpeg -hide_banner -loglevel error -y -i $rough -i $audio -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t $masterDurationText -movflags +faststart $clean
if ($LASTEXITCODE -ne 0) { throw "Failed to mux v004 clean master" }

$escapedAss = $subtitles.Replace('\','/').Replace(':','\:')
$escapedFonts = $fonts.Replace('\','/').Replace(':','\:')
& ffmpeg -hide_banner -loglevel error -y -i $clean -vf "ass='$escapedAss':fontsdir='$escapedFonts'" -map 0:v:0 -map 0:a:0 -c:v libx264 -preset slow -crf 18 -c:a copy -movflags +faststart $final
if ($LASTEXITCODE -ne 0) { throw "Failed to burn designed subtitles" }
Write-Output "Wrote $rough"
Write-Output "Wrote $clean"
Write-Output "Wrote $final"
