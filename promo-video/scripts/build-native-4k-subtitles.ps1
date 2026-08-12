param([string]$SourceVersion = "v011", [string]$Version = "v012-native-4k")

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectDir ("07-edit/subtitles/xykw-promo-designed-{0}.ass" -f $SourceVersion)
$output = Join-Path $projectDir ("07-edit/subtitles/xykw-promo-designed-{0}.ass" -f $Version)
$content = Get-Content -LiteralPath $source -Raw -Encoding UTF8
$content = $content.Replace("PlayResX: 1920", "PlayResX: 3840").Replace("PlayResY: 1080", "PlayResY: 2160")
$content = $content.Replace(
    "Style: Story,Alibaba PuHuiTi 3.0 55 Regular,48,&H00F7F3E8,&H00F7F3E8,&H00000000,&H00000000,0,0,0,0,100,100,1.2,0,1,0,0,2,180,180,68,1",
    "Style: Story,Alibaba PuHuiTi 3.0 55 Regular,96,&H00F7F3E8,&H00F7F3E8,&H00000000,&H00000000,0,0,0,0,100,100,2.4,0,1,0,0,2,360,360,136,1"
)
$content = $content.Replace(
    "Style: Side,Alibaba PuHuiTi 3.0 55 Regular,40,&H0020352D,&H0020352D,&H00000000,&H00000000,0,0,0,0,100,100,0.8,0,1,0,0,1,132,1180,76,1",
    "Style: Side,Alibaba PuHuiTi 3.0 55 Regular,80,&H0020352D,&H0020352D,&H00000000,&H00000000,0,0,0,0,100,100,1.6,0,1,0,0,1,264,2360,152,1"
)
[System.IO.File]::WriteAllText($output, $content, [System.Text.UTF8Encoding]::new($true))
Write-Output "Wrote $output"
