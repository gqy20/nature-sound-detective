param([string]$Version = "v012-native-4k", [switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$workspaceDir = Split-Path -Parent $projectDir
$configPath = Join-Path $projectDir ("video-config-{0}.json" -f $Version)
if (-not (Test-Path -LiteralPath $configPath)) {
    $configPath = Join-Path $projectDir "video-config-v012-native-4k.json"
}
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$width = [int]$config.master.width
$height = [int]$config.master.height
$fps = [int]$config.master.fps
$duration = [double]$config.master.duration
$durationText = $duration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
$background = $config.master.background
$sourceDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir $config.sourceRoot))
$sceneDir = Join-Path $projectDir ("07-edit/scene-renders-4k/{0}" -f $Version)
$outputDir = Join-Path $projectDir "08-exports/4k-native"
$rough = Join-Path $outputDir ("xykw-promo-rough-{0}.mp4" -f $Version)
$clean = Join-Path $outputDir ("xykw-promo-polish-{0}-clean.mp4" -f $Version)
$final = Join-Path $outputDir ("xykw-promo-polish-{0}.mp4" -f $Version)
$audio = Join-Path $projectDir "06-audio/mix/final-mix-v011.wav"
$subtitles = Join-Path $projectDir ("07-edit/subtitles/xykw-promo-designed-{0}.ass" -f $Version)
$fonts = Join-Path $env:LOCALAPPDATA "Microsoft/Windows/Fonts"
$manifestPath = Join-Path $outputDir ("xykw-promo-polish-{0}-manifest.json" -f $Version)
New-Item -ItemType Directory -Force -Path $sceneDir, $outputDir | Out-Null

if (-not (Test-Path -LiteralPath $audio)) { throw "Missing final audio mix: $audio" }
if (-not (Test-Path -LiteralPath $subtitles)) { throw "Missing 4K subtitles: $subtitles" }

$sceneFiles = @()
$sourceAudit = @()
foreach ($scene in $config.scenes) {
    $sceneDuration = [double]$scene.end - [double]$scene.start
    $sceneDurationText = $sceneDuration.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
    $scenePath = Join-Path $sceneDir ("{0}.mp4" -f $scene.id)
    $sceneFiles += $scenePath
    $inputPath = if ($scene.mode -eq "source") { Join-Path $sourceDir $scene.source } else { Join-Path $projectDir $scene.source }
    if (-not (Test-Path -LiteralPath $inputPath)) { throw "Missing scene source: $inputPath" }

    $probe = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of json -- $inputPath | ConvertFrom-Json
    $sourceAudit += [pscustomobject]@{
        id = $scene.id
        source = $inputPath
        source_width = [int]$probe.streams[0].width
        source_height = [int]$probe.streams[0].height
        scene_duration = $sceneDuration
    }

    if ((Test-Path -LiteralPath $scenePath) -and -not $Force) {
        Write-Output "Keep native 4K scene: $($scene.id)"
        continue
    }

    Write-Output "Rendering native 4K scene $($scene.id)"
    $phoneHeight = 2000
    $sourceVideoFilter = if ($scene.fullFrame) {
        "[0:v]scale=${width}:${height}:flags=lanczos,setsar=1[fg]"
    } elseif ($scene.sourceCropHeight) {
        $cropHeight = [double]$scene.sourceCropHeight
        "[0:v]crop=iw:ih*$cropHeight`:0:0,scale=-2:$phoneHeight`:flags=lanczos,setsar=1[fg]"
    } else {
        "[0:v]scale=-2:$phoneHeight`:flags=lanczos,setsar=1[fg]"
    }
    if ($scene.editorialOverlay) {
        $overlayPath = Join-Path $projectDir $scene.editorialOverlay
        $filter = "$sourceVideoFilter`;[1:v][fg]overlay=(W-w)/2:(H-h)/2:shortest=1[base];[base][3:v]overlay=0:0:shortest=1,format=yuv420p[v]"
        & ffmpeg -hide_banner -loglevel error -y -ss ([double]$scene.sourceStart) -t $sceneDurationText -i $inputPath -f lavfi -t $sceneDurationText -i "color=c=${background}:s=${width}x${height}:r=$fps" -f lavfi -t $sceneDurationText -i "anullsrc=r=48000:cl=stereo" -loop 1 -t $sceneDurationText -i $overlayPath -filter_complex $filter -map "[v]" -map 2:a:0 -r $fps -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 15 -b:v 0 -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart $scenePath
    } else {
        $filter = "$sourceVideoFilter`;[1:v][fg]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p[v]"
        & ffmpeg -hide_banner -loglevel error -y -ss ([double]$scene.sourceStart) -t $sceneDurationText -i $inputPath -f lavfi -t $sceneDurationText -i "color=c=${background}:s=${width}x${height}:r=$fps" -f lavfi -t $sceneDurationText -i "anullsrc=r=48000:cl=stereo" -filter_complex $filter -map "[v]" -map 2:a:0 -r $fps -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 15 -b:v 0 -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart $scenePath
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to render native 4K scene $($scene.id)" }
}

$ffargs = @("-hide_banner", "-loglevel", "error", "-y")
$filters = @()
for ($index = 0; $index -lt $sceneFiles.Count; $index++) {
    $ffargs += @("-i", $sceneFiles[$index])
    $scene = $config.scenes[$index]
    $sceneDuration = [double]$scene.end - [double]$scene.start
    $chain = "[$index`:v]fps=$fps,settb=expr=1/$fps,setpts=PTS-STARTPTS"
    if ($index -gt 0) { $chain += ",fade=t=in:st=0:d=0.12:color=0xF3F0E7" }
    if ($index -lt $sceneFiles.Count - 1) {
        $fadeStart = ($sceneDuration - 0.12).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)
        $chain += ",fade=t=out:st=$fadeStart`:d=0.12:color=0xF3F0E7"
    }
    $filters += "$chain[v$index]"
}
$concatInputs = (0..($sceneFiles.Count - 1) | ForEach-Object { "[v$_]" }) -join ""
$filters += "${concatInputs}concat=n=$($sceneFiles.Count):v=1:a=0,trim=duration=$durationText,setpts=PTS-STARTPTS,format=yuv420p[outv]"
$ffargs += @("-filter_complex", ($filters -join ";"), "-map", "[outv]", "-an", "-r", $fps, "-c:v", "h264_nvenc", "-preset", "p7", "-tune", "hq", "-rc", "vbr", "-cq", "16", "-b:v", "0", "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-movflags", "+faststart", $rough)
& ffmpeg @ffargs
if ($LASTEXITCODE -ne 0) { throw "Failed to build native 4K rough master" }

& ffmpeg -hide_banner -loglevel error -y -i $rough -i $audio -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -ar 48000 -t $durationText -movflags +faststart $clean
if ($LASTEXITCODE -ne 0) { throw "Failed to mux native 4K clean master" }

$escapedAss = $subtitles.Replace('\','/').Replace(':','\:')
$escapedFonts = $fonts.Replace('\','/').Replace(':','\:')
& ffmpeg -hide_banner -loglevel error -y -i $clean -vf "ass='$escapedAss':fontsdir='$escapedFonts'" -map 0:v:0 -map 0:a:0 -c:v h264_nvenc -preset p7 -tune hq -rc vbr -cq 18 -b:v 0 -pix_fmt yuv420p -c:a copy -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart $final
if ($LASTEXITCODE -ne 0) { throw "Failed to burn native 4K subtitles" }

$finalProbe = & ffprobe -v error -show_entries format=duration,size:stream=codec_name,codec_type,width,height,r_frame_rate,sample_rate,channels -of json -- $final | ConvertFrom-Json
$manifest = [pscustomobject]@{
    version = $Version
    config = $configPath
    output = $final
    clean_output = $clean
    width = $width
    height = $height
    fps = $fps
    duration = [double]$finalProbe.format.duration
    size_bytes = [long]$finalProbe.format.size
    sha256 = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
    clean_sha256 = (Get-FileHash -LiteralPath $clean -Algorithm SHA256).Hash
    source_audit = $sourceAudit
}
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
Write-Output "Wrote $clean"
Write-Output "Wrote $final"
Write-Output "Wrote $manifestPath"
