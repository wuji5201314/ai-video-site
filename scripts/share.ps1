<#
.SYNOPSIS
  一条命令把站点临时发布到公网，拿到一个别人能打开 https 链接。

.DESCRIPTION
  做三件事：
    1. 起本地静态服务器（如果没在跑）
    2. 起 cloudflared 隧道（没装就自动下载）
    3. 打印公网链接，按 Ctrl+C 停止

  不需要账号、不需要备案、不需要域名。电脑关了就断。
  要长期在线请用 GitHub Pages（见 README）。

.EXAMPLE
  .\scripts\share.ps1

.EXAMPLE
  .\scripts\share.ps1 -Port 8080
#>
param(
    [int]$Port = 5173
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$servePath = Join-Path $PSScriptRoot 'serve.mjs'

if (-not (Test-Path -LiteralPath $servePath)) { throw "serve.mjs missing: $servePath" }

function Test-PortOpen {
    param([int]$P)
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $P)
        $c.Close()
        return $true
    }
    catch { return $false }
}

# ---------- 1. 本地服务器 ----------
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { throw 'node not found - install Node.js first' }

if (Test-PortOpen -P $Port) {
    Write-Host "本地服务器已在 $Port 端口运行，复用。" -ForegroundColor DarkGray
    $serverProc = $null
}
else {
    $tryPort = $Port
    $guard = 0
    while ((Test-PortOpen -P $tryPort) -and $guard -lt 20) { $tryPort++; $guard++ }
    $Port = $tryPort
    Write-Host "启动本地服务器（端口 $Port）..." -ForegroundColor Cyan
    $serverProc = Start-Process -FilePath $node.Source `
        -ArgumentList @("`"$servePath`"", "`"$root`"", "$Port") `
        -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    if (-not (Test-PortOpen -P $Port)) { throw "server did not start on $Port" }
}

# ---------- 2. cloudflared ----------
function Find-Cloudflared {
    $local = Join-Path $PSScriptRoot 'cloudflared.exe'
    if (Test-Path -LiteralPath $local) { return $local }

    $cached = Join-Path $env:LOCALAPPDATA 'cfd\cloudflared.exe'
    if (Test-Path -LiteralPath $cached) { return $cached }

    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    return $null
}

$cf = Find-Cloudflared

if (-not $cf) {
    $dir = Join-Path $env:LOCALAPPDATA 'cfd'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $target = Join-Path $dir 'cloudflared.exe'
    $rel = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'

    Write-Host "没找到 cloudflared，正在下载（约 50MB）..." -ForegroundColor Cyan
    $mirrors = @(
        "https://ghfast.top/$rel",
        "https://gh-proxy.com/$rel",
        "https://hub.gitmirror.com/$rel",
        $rel
    )
    foreach ($m in $mirrors) {
        $host_ = ([Uri]$m).Host
        Write-Host "  试 $host_ ..." -ForegroundColor DarkGray
        Remove-Item $target -Force -ErrorAction SilentlyContinue
        & curl.exe -L --silent --show-error --max-time 120 --output $target $m 2>$null
        if ((Test-Path $target) -and (Get-Item $target).Length -gt 5MB) {
            Write-Host "  下载完成 $([math]::Round((Get-Item $target).Length/1MB,1)) MB" -ForegroundColor Green
            $cf = $target
            break
        }
    }
    if (-not $cf) { throw 'cloudflared download failed - check network or put cloudflared.exe in scripts\' }
}

# ---------- 3. 隧道 ----------
Write-Host "建立隧道..." -ForegroundColor Cyan
$logFile = Join-Path $env:TEMP 'cfd-tunnel.log'
$outFile = Join-Path $env:TEMP 'cfd-tunnel.out'
Remove-Item $logFile, $outFile -Force -ErrorAction SilentlyContinue

$cfProc = Start-Process -FilePath $cf `
    -ArgumentList @('tunnel', '--url', "http://127.0.0.1:$Port", '--no-autoupdate', '--protocol', 'http2') `
    -RedirectStandardError $logFile -RedirectStandardOutput $outFile `
    -WindowStyle Hidden -PassThru

$publicUrl = $null
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 500
    if ($cfProc.HasExited) { break }
    $txt = ''
    foreach ($f in @($logFile, $outFile)) {
        if (Test-Path -LiteralPath $f) { $txt += (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue) }
    }
    $m = [regex]::Match($txt, 'https://[a-z0-9][a-z0-9\-]*\.trycloudflare\.com')
    if ($m.Success) { $publicUrl = $m.Value; break }
}

if (-not $publicUrl) {
    if ($cfProc -and -not $cfProc.HasExited) { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue }
    if ($serverProc) { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue }
    $tail = ''
    if (Test-Path -LiteralPath $logFile) { $tail = (Get-Content -LiteralPath $logFile -Tail 15 -ErrorAction SilentlyContinue) -join "`n" }
    throw "隧道没起来。cloudflared 最后几行：`n$tail"
}

# ---------- 报告 ----------
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host "  公网地址（发给谁都能打开）：" -ForegroundColor Green
Write-Host ""
Write-Host "  $publicUrl" -ForegroundColor White
Write-Host ""
Write-Host "  本机预览: http://127.0.0.1:$Port/" -ForegroundColor DarkGray
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host "按 Ctrl+C 停止分享（链接立刻失效）。" -ForegroundColor Yellow
Write-Host ""

try {
    while (-not $cfProc.HasExited) { Start-Sleep -Seconds 2 }
    Write-Host "隧道已断开。" -ForegroundColor Yellow
}
finally {
    if ($cfProc -and -not $cfProc.HasExited) { Stop-Process -Id $cfProc.Id -Force -ErrorAction SilentlyContinue }
    if ($serverProc -and -not $serverProc.HasExited) { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue }
    Write-Host "已停止。" -ForegroundColor DarkGray
}