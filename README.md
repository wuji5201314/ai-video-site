# AI 视频作品集 · GitHub Pages 在线播放

把自己的 AI 视频做成一个能直接发链路的网页：手机、电脑、微信里点开就能播。

---

## 一、先回答"能不能"

**能。** 但有四条硬限制必须知道：

| 限制 | 数值 | 后果 |
|---|---|---|
| 单个文件 | **100 MB** | 超过直接被 `git push` 拒绝，不是警告 |
| 仓库大小 | 建议 < 1 GB | 超过后 clone 极慢，Pages 构建也会拖 |
| 站点发布总量 | 1 GB | 超过 Pages 会构建失败 |
| 流量 | 每月 100 GB 软限制 | 视频被刷爆会收到警告，站点可能被暂停 |

还有一条最容易踩的：**GitHub Pages 不解析 Git LFS**。你用 LFS 上传的大文件，网页上是 404，只有个指针文件。所以大视频别指望 LFS。

可行的三条路，按体积选：

| 你的情况 | 用哪个 | 为什么 |
|---|---|---|
| 每个视频 < 90 MB，总共 < 800 MB | **直接放 mp4** | 最简单，一个文件点击就能拖 |
| 单个视频几百 MB 到几 GB | **HLS 切片** | 切成 6 秒一片，每片几 MB，绕过 100MB 限制，还能秒开、随便拖 |
| 流量大 / 视频特别多 | **视频放外部（Cloudflare R2 等），Pages 只放网页** | 不占 GitHub 带宽，也不占仓库 |

这个项目三条都支持，`videos.js` 里填不同的字段就行。

---

## 二、5 分钟上线

### 1. 确认 ffmpeg 能用

先开一个新终端试：

```powershell
ffmpeg -version
```

有版本号就直接跳到第 2 步。报"不是内部或外部命令"的话，你机器上其实已经有 ffmpeg 了，只是没接进 PATH。这个项目的脚本会自动按下面顺序找，找到一个就用：

1. PATH 里的 `ffmpeg`
2. `C:\ffmpeg\bin\ffmpeg.exe`
3. `%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe`
4. `%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin\ffmpeg.exe`
5. `%USERPROFILE%\.dsh\projects\*\node_modules\ffmpeg-static\ffmpeg.exe`

想彻底装一个干净的：

```powershell
winget install --id Gyan.FFmpeg -e
```

装完**重开终端**（PATH 要重新加载），`ffmpeg -version` 有输出就行。

> 已经确认这台机器 `C:\ffmpeg\bin\ffmpeg.exe` 就位（6.1.1，带 libx264 / HLS / faststart），可以直接用。


### 2. 转码你的视频

```powershell
cd C:\Users\wuji\ai-video-site

# 普通情况：转成网页 mp4（H.264 + faststart，手机/Safari/微信都能播）
.\scripts\to-web.ps1 -Input "D:\raw\我的视频.mp4"

# 文件大：切成 HLS
.\scripts\to-web.ps1 -Input "D:\raw\big.mp4" -Mode hls -Height 720 -Crf 26

# 两个都要（mp4 给小文件用，HLS 给大文件用）
.\scripts\to-web.ps1 -Input "D:\raw\big.mp4" -Mode both
```

脚本会顺手生成封面图，并在最后打印一行可以直接粘贴的配置，比如：

```js
{ title: 'demo', src: 'media/demo.mp4', poster: 'media/demo.jpg' }
```

> `media/selftest.mp4` + `selftest.jpg` + `hls/selftest/` 是自检产物，用来确认链路是通的。
> 你自己第一条视频配好之后，把 `videos.js` 里那条"示例视频（可删）"和这些文件删掉即可。

### 3. 把视频登记到 `videos.js`

打开 [videos.js](videos.js)，把上面那行粘进 `window.VIDEOS = [ ... ]` 里。想加几条加几条。

字段说明：

```js
{
  title: '标题',            // 必填
  src: 'media/a.mp4',      // 二选一：直接可播的文件
  hls: 'hls/a/index.m3u8', // 二选一：HLS 播放列表（大文件）
  poster: 'media/a.jpg',   // 可选：封面
  desc: '一句话简介',       // 可选
  date: '2026-11',         // 可选
  portrait: true           // 可选：竖屏视频写 true，卡片画框变 3:4
}
```

> `src` 和 `hls` 至少写一个；两个都写时优先用 `src`。
> **竖屏视频一定要写 `portrait: true`**，否则 16:9 的卡片会把封面上下裁掉一大块。
> 路径都相对于 `index.html`，**不要以 `/` 开头**，大小写要和实际文件完全一致（GitHub 区分大小写）。

### 4. 建仓库并推上去

先在 GitHub 网页上新建一个 **Public** 仓库（不要勾选 "Add a README file"），然后：

```powershell
cd C:\Users\wuji\ai-video-site
git init -b main
git add .
git commit -m "init"
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

### 5. 打开 Pages

仓库页面 → **Settings** → 左侧 **Pages** → "Build and deployment" 的 **Source** 选 **GitHub Actions**。

推完代码后 Actions 会自动跑一次，1~2 分钟后地址是：

```
https://<你的用户名>.github.io/<仓库名>/
```

如果仓库名就叫 `<你的用户名>.github.io`，地址就是 `https://<你的用户名>.github.io/`。

### 6. 以后加视频

**一条命令搞定（推荐）**：

```powershell
.\scripts\add-video.ps1 "D:\新视频.mp4"
```

它会转码、截封面、探测是不是竖屏、自动把条目写进 `videos.js`。跑完刷新网页就能看到。

想改标题和简介：

```powershell
.\scripts\add-video.ps1 "D:\新视频.mp4" -Title "星际旅人 · 15s" -Desc "用 Kling 生成，15 秒"
```

大文件：

```powershell
.\scripts\add-video.ps1 "D:\大文件.mp4" -Mode hls
```

其他参数：`-Name`（文件名，默认从源文件名生成）、`-Crf`（画质，默认 23，越小越清楚越大）、`-Height`（默认 1080）、`-Portrait` / `-NoPortrait`（强制指定竖屏/横屏，一般不写，脚本自己判断）、`-Force`（重名也覆盖条目）。

**手动方式**：`.\scripts\to-web.ps1` 转码，然后照第三节的字段说明在 `videos.js` 里加一段。

**推上去**：

```powershell
git add .
git commit -m "add video"
git push
```

等 Actions 绿了就生效。单条视频可以直接分享：`https://.../index.html#v2`（数字是它在 `VIDEOS` 数组里的位置，从 0 开始）。

---

## 附：不等 Actions，立刻让别人访问

GitHub Pages 要等 push + 构建。想马上把链接发出去，用隧道：

```powershell
.\scripts\share.ps1
```

输出像这样：

```
================================================
  公网地址（发给谁都能打开）：

  https://coordinator-asking-links-drinks.trycloudflare.com

  本机预览: http://127.0.0.1:5173/
================================================

按 Ctrl+C 停止分享（链接立刻失效）。
```

这个链接手机 4G、别人电脑都能直接打开，不需要对方装东西、也没有警告页。

**特点**：

- 不用账号、不用域名、不用备案
- 流量走 Cloudflare，不占你的上传带宽（你的电脑只上传一次）
- 地址每次重启都变
- **电脑关机 / 关掉窗口 / 断网，链接立刻失效**
- 电脑要一直开着

第一次运行会自动下载 cloudflared（约 50MB，走镜像）。之后从 `%LOCALAPPDATA%\cfd\` 复用。

> 想长期稳定在线，还是用上面的 GitHub Pages。隧道只适合"现在就让朋友看一眼"。

---

## 三、常见问题

**页面 404 / 一直转圈**
Pages 的 Source 没设成 GitHub Actions，或者你在别的分支上推的（工作流只监听 `main`）。

**视频框是黑的，点播放报错**
编码不对。用 `to-web.ps1` 重转一次——它固定输出 H.264 High + yuv420p + AAC，这是唯一全平台都认的组合。手机拍的 HEVC/H.265、录屏的 VP9 都可能放不出来。

**拖动进度条要等半天 / 卡住**
mp4 少了 faststart（索引写在文件末尾，必须先下完才能拖）。脚本里带了 `-movflags +faststart`，重新转一次就好。

**视频 404，但本地能打开**
99% 是大小写。`Media/Demo.MP4` ≠ `media/demo.mp4`。

**push 被拒：file is 123.45 MB; this exceeds GitHub's file size limit of 100.00 MB**
改用 `-Mode hls`，不要在仓库里留大文件。如果已经误提交了，需要从历史里删掉（`git filter-repo`），光删文件不够。

**想放更多更大的视频**
把视频丢到 Cloudflare R2 / Backblaze B2 / 任意支持外链的存储，`videos.js` 里直接写完整 URL：

```js
{ title: 'x', src: 'https://your-bucket.example.com/x.mp4' }
```

跨域播放记得在存储那边配 CORS（允许 GET + Range）。Pages 只负责网页本身，不再吃你的 100GB 带宽。

---

## 四、项目结构

```
ai-video-site/
├─ index.html                # 页面
├─ videos.js                 # ← 你唯一需要改的文件
├─ assets/
│  ├─ style.css              # 样式（暗色、响应式）
│  └─ app.js                 # 列表渲染 + 播放器逻辑
├─ media/                    # 放 mp4 和封面 jpg
├─ hls/                      # 切片输出（每个视频一个子目录）
│  └─ <名字>/index.m3u8
├─ scripts/
│  ├─ to-web.ps1             # 转码 / 切片 / 出封面
│  ├─ add-video.ps1          # 一条命令：转码 + 写 videos.js
│  ├─ serve.mjs              # 本地预览服务器（支持 Range）
│  └─ share.ps1              # 一条命令：临时发布到公网
├─ .github/workflows/pages.yml  # 自动部署
└─ .nojekyll                 # 关掉 Jekyll，避免特殊目录被吞
```

---

## 五、本地预览

别双击 `index.html`（`file://` 下部分浏览器会拦 fetch/HLS），起个本地服务：

```powershell
cd C:\Users\wuji\ai-video-site
npx --yes serve . -p 5173
```

然后浏览器打开 http://localhost:5173 。
