<#
.SYNOPSIS
  一条命令把新视频加进站点：转码 + 出封面 + 自动写进 videos.js。

.DESCRIPTION
  做四件事：
    1. 调 to-web.ps1 转码（mp4 或 hls）
    2. 出封面图
    3. 探测分辨率，竖屏自动加 portrait: true
    4. 把条目插到 videos.js 的 window.VIDEOS 数组末尾

  跑完直接刷新网页就能看到，不用手动改任何文件。

.EXAMPLE
  .\scripts\add-video.ps1 "D:\新视频.mp4"

.EXAMPLE
  .\scripts\add-video.ps1 "D:\新视频.mp4" -Title "星际旅人 · 15s" -Desc "用 Kling 生成"

.EXAMPLE
  .\scripts\add-video.ps1 "D:\大文件.mp4" -Mode hls
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][Alias('Input')][string]$Source,
    [string]$Title,
    [string]$Desc,
    [string]$Name,
    [string]$Date,
    [ValidateSet('mp4', 'hls', 'both')][string]$Mode = 'mp4',
    [int]$Crf = 23,
    [int]$Height = 1080,
    [switch]$Portrait,
    [switch]$NoPortrait,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$videosJs = Join-Path $root 'videos.js'
$mediaDir = Join-Path $root 'media'

if (-not (Test-Path -LiteralPath $Source)) { throw "Not found: $Source" }
if (-not (Test-Path -LiteralPath $videosJs)) { throw "videos.js missing at $videosJs" }

# ---------- 名字 ----------
if (-not $Name) { $Name = [IO.Path]::GetFileNameWithoutExtension($Source) }
$Name = ($Name -replace '[^\w\-]+', '-').Trim('-')
if (-not $Name) { $Name = 'video' }

if (-not $Title) { $Title = [IO.Path]::GetFileNameWithoutExtension($Source) }

# ---------- 找 ffmpeg（和 to-web.ps1 同一套顺序）----------
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
if (-not $ffmpeg) { throw 'ffmpeg not found - run scripts\to-web.ps1 once to see the install hint' }

# ffmpeg 把信息写到 stderr，且单独 -i 时 exit code 是 1，所以不判断退出码
function Get-VideoInfo {
    param([string]$Path)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = @(& $ffmpeg -hide_banner -nostdin -i $Path 2>&1 | ForEach-Object { "$_" })
    }
    finally {
        $ErrorActionPreference = $prev
    }

    $w = 0; $h = 0; $dur = 0
    foreach ($line in $out) {
        if ($w -eq 0 -and $line -match 'Stream #\d+:\d+.*Video:.*?,\s*(\d{2,5})x(\d{2,5})') {
            $w = [int]$Matches[1]
            $h = [int]$Matches[2]
        }
        if ($dur -eq 0 -and $line -match 'Duration:\s*(\d+):(\d+):(\d+)\.(\d+)') {
            $dur = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3]
            if ($dur -eq 0 -and [int]$Matches[4] -gt 0) { $dur = 1 }
        }
    }
    return @{ Width = $w; Height = $h; Duration = $dur }
}

$info = Get-VideoInfo $Source
$isPortrait = $false
if ($Portrait) { $isPortrait = $true }
elseif ($NoPortrait) { $isPortrait = $false }
elseif ($info.Width -gt 0 -and $info.Height -gt 0) { $isPortrait = ($info.Height -gt $info.Width) }

# ---------- 转码 ----------
$toWeb = Join-Path $PSScriptRoot 'to-web.ps1'
$args = @{ Source = $Source; Name = $Name; Mode = $Mode; Crf = $Crf; Height = $Height }
& $toWeb @args
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
    # to-web.ps1 用 throw 时会往上抛，这里只是兜底
}

$mp4Path = Join-Path $mediaDir "$Name.mp4"
$hlsPath = Join-Path $root "hls\$Name\index.m3u8"
$jpgPath = Join-Path $mediaDir "$Name.jpg"

$use = ''
if (($Mode -eq 'mp4' -or $Mode -eq 'both') -and (Test-Path -LiteralPath $mp4Path)) { $use = 'mp4' }
elseif (($Mode -eq 'hls' -or $Mode -eq 'both') -and (Test-Path -LiteralPath $hlsPath)) { $use = 'hls' }
if (-not $use) { throw "转码产物没找到（$mp4Path / $hlsPath）" }

# ---------- 写 videos.js ----------
function ConvertTo-JsString {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return ($s -replace '\\', '\\' -replace "'", "\'" -replace "`r?`n", ' ')
}

function Find-ObjectBrace {
    # 在 [ ... ] 之间找到最后一个顶层 } 的位置
    param([string]$Text, [int]$OpenIdx)
    $n = $Text.Length
    $arr = 0
    $obj = 0
    $lastBrace = -1
    $endIdx = -1
    $i = $OpenIdx
    $inStr = $false
    $q = [char]0

    while ($i -lt $n) {
        $c = $Text[$i]

        if ($inStr) {
            if ($c -eq [char]'\') { $i += 2; continue }
            if ($c -eq $q) { $inStr = $false }
            $i++; continue
        }

        if ($c -eq [char]'/' -and ($i + 1) -lt $n) {
            $n1 = $Text[$i + 1]
            if ($n1 -eq [char]'/') {
                $j = $Text.IndexOf("`n", $i)
                if ($j -lt 0) { break }
                $i = $j; continue
            }
            if ($n1 -eq [char]'*') {
                $j = $Text.IndexOf('*/', $i + 2)
                if ($j -lt 0) { break }
                $i = $j + 2; continue
            }
        }

        if ($c -eq [char]"'" -or $c -eq [char]'"' -or $c -eq [char]'`') { $inStr = $true; $q = $c; $i++; continue }

        if ($c -eq [char]'[') { $arr++ }
        elseif ($c -eq [char]']') {
            $arr--
            if ($arr -eq 0) { $endIdx = $i; break }
        }
        elseif ($c -eq [char]'{') { $obj++ }
        elseif ($c -eq [char]'}') {
            $obj--
            if ($arr -eq 1 -and $obj -eq 0) { $lastBrace = $i }
        }
        $i++
    }
    return @{ End = $endIdx; LastBrace = $lastBrace }
}

$text = [IO.File]::ReadAllText($videosJs)

if (-not $Force) {
    $dupe = [regex]::Escape("media/$Name.mp4")
    $dupe2 = [regex]::Escape("hls/$Name/index.m3u8")
    if ($text -match $dupe -or $text -match $dupe2) {
        Write-Host ""
        Write-Host "'$Name' 已经在 videos.js 里了。" -ForegroundColor Yellow
        Write-Host "想覆盖条目就加 -Force；只换了视频文件的话不用改 videos.js，直接刷新网页。" -ForegroundColor DarkGray
        exit 0
    }
}

$m = [regex]::Match($text, 'window\.VIDEOS\s*=\s*\[')
if (-not $m.Success) { throw 'videos.js 里没找到 window.VIDEOS = [' }

$openIdx = $m.Index + $m.Length - 1
$scan = Find-ObjectBrace -Text $text -OpenIdx $openIdx
if ($scan.End -lt 0) { throw 'videos.js 的数组括号不配对，先手动修一下' }

# 条目
if (-not $Date) { $Date = (Get-Date).ToString('yyyy-MM') }
$descText = $Desc
if (-not $descText) {
    $bits = @()
    if ($info.Duration -gt 0) { $bits += "$($info.Duration) 秒" }
    if ($info.Height -gt 0) { $bits += "原片 $($info.Width)x$($info.Height)" }
    $descText = ($bits -join '，')
}

$lines = @()
$lines += '{'
$lines += "    title: '$(ConvertTo-JsString $Title)',"
if ($use -eq 'mp4') { $lines += "    src: 'media/$Name.mp4'," }
else { $lines += "    hls: 'hls/$Name/index.m3u8'," }
if (Test-Path -LiteralPath $jpgPath) { $lines += "    poster: 'media/$Name.jpg'," }
if ($descText) { $lines += "    desc: '$(ConvertTo-JsString $descText)'," }
$lines += "    date: '$Date',"
if ($isPortrait) { $lines += "    portrait: true," }
$lines = $lines[0..($lines.Count - 1)]
$lastLine = $lines[$lines.Count - 1]
$lines[$lines.Count - 1] = $lastLine.TrimEnd(',')
$lines += '  }'
$entry = ($lines -join "`n")

if ($scan.LastBrace -ge 0) {
    $insertAt = $scan.LastBrace + 1
    $ins = ",`n`n  " + $entry
}
else {
    # 空数组（可能只有注释）：插在 [ 后面
    $insertAt = $openIdx + 1
    $ins = "`n  " + $entry + "`n"
}

$newText = $text.Substring(0, $insertAt) + $ins + $text.Substring($insertAt)
[IO.File]::WriteAllText($videosJs, $newText, (New-Object System.Text.UTF8Encoding($false)))

# ---------- 报告 ----------
Write-Host ""
Write-Host "已写入 videos.js：" -ForegroundColor Green
Write-Host $entry -ForegroundColor White
Write-Host ""
if ($isPortrait) { Write-Host "检测到竖屏（$($info.Width)x$($info.Height)），已加 portrait: true" -ForegroundColor Cyan }
Write-Host "刷新网页就能看到：http://127.0.0.1:5173/" -ForegroundColor Cyan
Write-Host ""
Write-Host "上传到 GitHub 后，这几步就是全部：" -ForegroundColor DarkGray
Write-Host "  git add -A; git commit -m 'add $Name'; git push" -ForegroundColor DarkGray