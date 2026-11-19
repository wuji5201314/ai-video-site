<#
.SYNOPSIS
  把视频转成适合 GitHub Pages 在线播放的格式。

.DESCRIPTION
  mp4 模式：H.264 + AAC + faststart，Safari / 微信内置浏览器都能播。
  hls 模式：切成 6 秒一片，绕过 GitHub 单文件 100MB 硬限制。

.EXAMPLE
  .\scripts\to-web.ps1 -Input "D:\raw\a.mov"

.EXAMPLE
  .\scripts\to-web.ps1 -Input "D:\raw\big.mp4" -Mode hls -Height 720 -Crf 26

.EXAMPLE
  .\scripts\to-web.ps1 -Input "D:\raw\big.mp4" -Mode both
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][Alias('Input')][string]$Source,
    [string]$Name,
    [ValidateSet('mp4', 'hls', 'both')][string]$Mode = 'mp4',
    [int]$Crf = 23,
    [int]$Height = 1080,
    [switch]$NoCover
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$mediaDir = Join-Path $root 'media'
$hlsDir = Join-Path $root 'hls'

if (-not (Test-Path -LiteralPath $Source)) { throw "Not found: $Source" }

# ---------- locate ffmpeg ----------
function Find-Ffmpeg {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add('C:\ffmpeg\bin\ffmpeg.exe')
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe'))
    $candidates.Add('C:\Program Files\ffmpeg\bin\ffmpeg.exe')

    $globs = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin\ffmpeg.exe'),
        (Join-Path $env:USERPROFILE '.dsh\projects\*\node_modules\ffmpeg-static\ffmpeg.exe')
    )
    foreach ($g in $globs) {
        Get-ChildItem -Path $g -ErrorAction SilentlyContinue | ForEach-Object { $candidates.Add($_.FullName) }
    }

    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

$ffmpeg = Find-Ffmpeg
if (-not $ffmpeg) {
    Write-Host "ffmpeg not found. Install it with:" -ForegroundColor Yellow
    Write-Host "    winget install --id Gyan.FFmpeg -e" -ForegroundColor Cyan
    throw 'ffmpeg missing'
}

# ffmpeg 把日志写到 stderr。$ErrorActionPreference='Stop' 会把它当致命错误，
# 所以这里临时切回 Continue，并且只在失败时把日志打出来。
function Invoke-FFmpeg {
    param([string[]]$ArgList)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $lines = @()
    $code = 1
    try {
        $lines = @(& $ffmpeg @ArgList 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0) {
        foreach ($l in $lines) { Write-Host "    $l" -ForegroundColor DarkYellow }
    }
    return $code
}

if (-not $Name) { $Name = [IO.Path]::GetFileNameWithoutExtension($Source) }
$Name = ($Name -replace '[\\/:*?"<>|\s]+', '-').Trim('-')
if (-not $Name) { $Name = 'video' }

New-Item -ItemType Directory -Force -Path $mediaDir, $hlsDir | Out-Null

# 统一编码参数：yuv420p 保证 Safari / 微信能解，固定 GOP 让拖动更顺
$scaleExpr = "scale=-2:'min($Height,ih)'"
$baseArgs = @(
    '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
    '-i', $Source,
    '-c:v', 'libx264',
    '-preset', 'veryfast',
    '-crf', "$Crf",
    '-profile:v', 'high',
    '-pix_fmt', 'yuv420p',
    '-vf', $scaleExpr,
    '-g', '48',
    '-keyint_min', '48',
    '-sc_threshold', '0',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-ac', '2',
    '-ar', '48000'
)

Write-Host ""
Write-Host "input : $Source" -ForegroundColor Cyan
Write-Host "name  : $Name" -ForegroundColor Cyan
Write-Host "ffmpeg: $ffmpeg" -ForegroundColor DarkGray
Write-Host ""

# ---------- cover ----------
if (-not $NoCover) {
    $cover = Join-Path $mediaDir "$Name.jpg"
    Write-Host "[cover] $cover" -ForegroundColor Green
    $code = Invoke-FFmpeg @(
        '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
        '-ss', '1', '-i', $Source,
        '-frames:v', '1', '-q:v', '3',
        '-vf', "scale=-2:'min(720,ih)'",
        $cover
    )
    if ($code -ne 0) {
        # 视频短于 1 秒时 -ss 1 会取不到帧，退回到第 0 帧
        $code = Invoke-FFmpeg @(
            '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
            '-i', $Source,
            '-frames:v', '1', '-q:v', '3',
            '-vf', "scale=-2:'min(720,ih)'",
            $cover
        )
    }
    if ($code -ne 0) { Write-Host "        cover failed, skipped" -ForegroundColor DarkYellow }
}

# ---------- mp4 ----------
if ($Mode -eq 'mp4' -or $Mode -eq 'both') {
    $outMp4 = Join-Path $mediaDir "$Name.mp4"
    Write-Host "[mp4]  -> $outMp4" -ForegroundColor Green
    $code = Invoke-FFmpeg ($baseArgs + @('-movflags', '+faststart', $outMp4))
    if ($code -ne 0) { throw 'mp4 encode failed' }
    $mb = [math]::Round((Get-Item -LiteralPath $outMp4).Length / 1MB, 1)
    Write-Host "        $mb MB" -ForegroundColor DarkGray
    if ($mb -gt 95) {
        Write-Host "        over 95MB - GitHub will reject it, use -Mode hls instead" -ForegroundColor Yellow
    }
}

# ---------- hls ----------
if ($Mode -eq 'hls' -or $Mode -eq 'both') {
    $outDir = Join-Path $hlsDir $Name
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $playlist = Join-Path $outDir 'index.m3u8'
    $segPattern = Join-Path $outDir 'seg_%05d.ts'
    Write-Host "[hls]  -> $playlist" -ForegroundColor Green
    $code = Invoke-FFmpeg ($baseArgs + @(
        '-f', 'hls',
        '-hls_time', '6',
        '-hls_playlist_type', 'vod',
        '-hls_list_size', '0',
        '-hls_segment_filename', $segPattern,
        $playlist
    ))
    if ($code -ne 0) { throw 'hls encode failed' }
    $segs = @(Get-ChildItem -LiteralPath $outDir -Filter '*.ts' -ErrorAction SilentlyContinue)
    $maxMb = 0
    if ($segs.Count -gt 0) {
        $maxMb = [math]::Round((($segs | Measure-Object Length -Maximum).Maximum) / 1MB, 2)
    }
    Write-Host "        $($segs.Count) segments, largest $maxMb MB" -ForegroundColor DarkGray
}

# ---------- next step ----------
Write-Host ""
Write-Host "Add this line to videos.js:" -ForegroundColor Cyan
if ($Mode -eq 'mp4' -or $Mode -eq 'both') {
    Write-Host "  { title: '$Name', src: 'media/$Name.mp4', poster: 'media/$Name.jpg' }" -ForegroundColor White
}
if ($Mode -eq 'hls' -or $Mode -eq 'both') {
    Write-Host "  { title: '$Name', hls: 'hls/$Name/index.m3u8', poster: 'media/$Name.jpg' }" -ForegroundColor White
}
Write-Host ""
