param(
    [switch]$Force,
    [string[]]$SceneIds,
    [string]$Version = "v001"
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $projectDir "video-config.json"
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir $config.sourceRoot))
$sceneDir = Join-Path $projectDir "07-edit/scene-renders"
$exportDir = Join-Path $projectDir "08-exports/review"
$concatPath = Join-Path $projectDir "07-edit/timelines/rough-cut-concat.txt"
$reviewPath = Join-Path $exportDir ("xykw-promo-rough-{0}.mp4" -f $Version)
New-Item -ItemType Directory -Force -Path $sceneDir, $exportDir, (Split-Path -Parent $concatPath) | Out-Null

$reviewWidth = [int]$config.master.reviewWidth
$reviewHeight = [int]$config.master.reviewHeight
$fps = [int]$config.master.fps
$background = $config.master.background
$sceneFiles = @()

foreach ($scene in $config.scenes) {
    $duration = [double]$scene.end - [double]$scene.start
    $scenePath = Join-Path $sceneDir ("{0}-{1}.mp4" -f $scene.id, ($scene.title -replace '[\\/:*?"<>|]', '_'))
    $sceneFiles += $scenePath
    $selectedForRender = -not $SceneIds -or $SceneIds -contains $scene.id
    if (-not $selectedForRender) {
        if (-not (Test-Path -LiteralPath $scenePath)) {
            throw "Scene $($scene.id) is missing; include it in -SceneIds or render the full cut"
        }
        Write-Output "Keep existing scene: $($scene.id)"
        continue
    }
    if ((Test-Path -LiteralPath $scenePath) -and -not $Force) {
        Write-Output "Skip existing scene: $($scene.id)"
        continue
    }

    Write-Output "Rendering $($scene.id): $($scene.title)"
    if ($scene.mode -eq "source" -or $scene.mode -eq "motion") {
        $inputPath = if ($scene.mode -eq "motion") { Join-Path $projectDir $scene.source } else { Join-Path $sourceDir $scene.source }
        $sourceVideoFilter = if ($scene.sourceCropHeight) {
            $cropHeight = [double]$scene.sourceCropHeight
            "[0:v]crop=iw:ih*$cropHeight`:0:0,scale=-2:$($reviewHeight - 80):flags=lanczos,setsar=1[fg]"
        } else {
            "[0:v]scale=-2:$($reviewHeight - 80):flags=lanczos,setsar=1[fg]"
        }
        if ($scene.editorialOverlay) {
            $overlayPath = Join-Path $projectDir $scene.editorialOverlay
            $filter = "$sourceVideoFilter`;[1:v][fg]overlay=(W-w)/2:(H-h)/2:shortest=1[base];[base][3:v]overlay=0:0:shortest=1,format=yuv420p[v]"
            & ffmpeg -hide_banner -loglevel error -y -ss ([double]$scene.sourceStart) -t $duration -i $inputPath -f lavfi -t $duration -i "color=c=${background}:s=${reviewWidth}x${reviewHeight}:r=$fps" -f lavfi -t $duration -i "anullsrc=r=48000:cl=stereo" -loop 1 -t $duration -i $overlayPath -filter_complex $filter -map "[v]" -map 2:a:0 -c:v libx264 -preset veryfast -crf 20 -r $fps -c:a aac -b:a 128k -shortest -movflags +faststart $scenePath
        } else {
            $filter = "$sourceVideoFilter`;[1:v][fg]overlay=(W-w)/2:(H-h)/2:shortest=1,format=yuv420p[v]"
            & ffmpeg -hide_banner -loglevel error -y -ss ([double]$scene.sourceStart) -t $duration -i $inputPath -f lavfi -t $duration -i "color=c=${background}:s=${reviewWidth}x${reviewHeight}:r=$fps" -f lavfi -t $duration -i "anullsrc=r=48000:cl=stereo" -filter_complex $filter -map "[v]" -map 2:a:0 -c:v libx264 -preset veryfast -crf 22 -r $fps -c:a aac -b:a 128k -shortest -movflags +faststart $scenePath
        }
    } else {
        $label = "$($scene.id)  $($scene.placeholder)"
        $fontPath = "C\:/Windows/Fonts/arial.ttf"
        $draw = "drawtext=fontfile='$fontPath':text='$label':fontcolor=0x163E32:fontsize=54:x=(w-text_w)/2:y=(h-text_h)/2"
        & ffmpeg -hide_banner -loglevel error -y -f lavfi -t $duration -i "color=c=${background}:s=${reviewWidth}x${reviewHeight}:r=$fps" -f lavfi -t $duration -i "anullsrc=r=48000:cl=stereo" -vf $draw -map 0:v:0 -map 1:a:0 -c:v libx264 -preset veryfast -crf 22 -r $fps -c:a aac -b:a 128k -shortest -movflags +faststart $scenePath
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to render scene $($scene.id)"
    }
}

$concatLines = $sceneFiles | ForEach-Object { "file '$($_.Replace("'", "''"))'" }
[System.IO.File]::WriteAllLines($concatPath, $concatLines, [System.Text.UTF8Encoding]::new($false))
& ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i $concatPath -c copy -movflags +faststart $reviewPath
if ($LASTEXITCODE -ne 0) {
    throw "Failed to concatenate rough cut"
}
Write-Output "Wrote $reviewPath"
