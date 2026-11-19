/* ===== AI 视频作品集 · 逻辑 =====
 * 数据来自 videos.js：window.VIDEOS = [{ title, src?, hls?, poster?, desc?, date? }, ...]
 * src  : 直接可播的 mp4/webm 路径（推荐，兼容性最好）
 * hls  : m3u8 播放列表路径（大视频用，绕过 GitHub 单文件 100MB 限制）
 * 优先使用 src；没有 src 时自动走 hls。
 */
(function () {
  'use strict';

  var HLS_CDN = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.17/dist/hls.min.js';

  var site = window.SITE || {};
  var videos = Array.isArray(window.VIDEOS) ? window.VIDEOS.filter(isUsable) : [];

  var $grid = document.getElementById('grid');
  var $empty = document.getElementById('empty');
  var $modal = document.getElementById('modal');
  var $player = document.getElementById('player');
  var $title = document.getElementById('modal-title');
  var $desc = document.getElementById('modal-desc');

  var hlsInstance = null;
  var hlsLibPromise = null;
  var currentIndex = -1;

  /* ---------- 站点文案 ---------- */
  if (site.title) document.getElementById('site-title').textContent = site.title;
  if (site.subtitle) document.getElementById('site-sub').textContent = site.subtitle;
  if (site.footer) document.getElementById('site-foot').textContent = site.footer;
  if (site.title) document.title = site.title;

  /* ---------- 工具 ---------- */
  function isUsable(v) {
    return v && (typeof v.src === 'string' && v.src || typeof v.hls === 'string' && v.hls);
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function loadHlsLib() {
    if (window.Hls) return Promise.resolve(window.Hls);
    if (!hlsLibPromise) {
      hlsLibPromise = new Promise(function (resolve, reject) {
        var s = document.createElement('script');
        s.src = HLS_CDN;
        s.async = true;
        s.onload = function () { window.Hls ? resolve(window.Hls) : reject(new Error('hls.js 载入后未挂载全局对象')); };
        s.onerror = function () { reject(new Error('hls.js 下载失败')); };
        document.head.appendChild(s);
      });
    }
    return hlsLibPromise;
  }

  /* ---------- 渲染列表 ---------- */
  function render() {
    if (!videos.length) {
      $empty.hidden = false;
      return;
    }
    var frag = document.createDocumentFragment();

    videos.forEach(function (v, i) {
      var card = el('button', 'card');
      card.type = 'button';
      card.setAttribute('aria-label', '播放：' + (v.title || '未命名'));

      var thumb = el('div', v.portrait ? 'thumb portrait' : 'thumb');
      if (v.poster) {
        var img = el('img');
        img.src = v.poster;
        img.alt = '';
        img.loading = 'lazy';
        img.decoding = 'async';
        thumb.appendChild(img);
      }
      var badge = el('div', 'play-badge');
      badge.appendChild(el('span', null, '▶'));
      thumb.appendChild(badge);

      var body = el('div', 'card-body');
      body.appendChild(el('h3', null, v.title || '未命名'));
      var meta = v.desc || v.date || '';
      if (meta) body.appendChild(el('p', null, meta));

      card.appendChild(thumb);
      card.appendChild(body);
      card.addEventListener('click', function () { open(i); });

      frag.appendChild(card);
    });

    $grid.appendChild(frag);
  }

  /* ---------- 播放控制 ---------- */
  function teardownPlayer() {
    if ($player) {
      try { $player.pause(); } catch (e) {}
      $player.removeAttribute('src');
      $player.removeAttribute('poster');
      $player.load();
    }
    if (hlsInstance) {
      try { hlsInstance.destroy(); } catch (e) {}
      hlsInstance = null;
    }
  }

  function playMp4(src) {
    $player.src = src;
    $player.load();
    var p = $player.play();
    if (p && p.catch) p.catch(function () { /* 自动播放被拦截，等用户点播放键 */ });
  }

  function playHls(src) {
    return loadHlsLib().then(function (Hls) {
      if (Hls.isSupported()) {
        hlsInstance = new Hls({ maxBufferLength: 30, enableWorker: true });
        hlsInstance.loadSource(src);
        hlsInstance.attachMedia($player);
        hlsInstance.on(Hls.Events.MANIFEST_PARSED, function () {
          var p = $player.play();
          if (p && p.catch) p.catch(function () {});
        });
        hlsInstance.on(Hls.Events.ERROR, function (_evt, data) {
          if (data && data.fatal) {
            console.warn('[hls] 致命错误', data.type, data.details);
          }
        });
      } else if ($player.canPlayType('application/vnd.apple.mpegurl')) {
        // Safari / iOS 原生 HLS
        $player.src = src;
        var p = $player.play();
        if (p && p.catch) p.catch(function () {});
      } else {
        throw new Error('当前浏览器不支持 HLS');
      }
    });
  }

  function open(index) {
    var v = videos[index];
    if (!v) return;

    currentIndex = index;
    $title.textContent = v.title || '未命名';
    $desc.textContent = v.desc || '';
    $desc.hidden = !v.desc;

    $modal.hidden = false;
    $modal.setAttribute('aria-hidden', 'false');
    document.body.style.overflow = 'hidden';

    teardownPlayer();

    // 先挂封面，避免加载首帧前是一块黑屏
    if (v.poster) $player.poster = v.poster;

    if (v.src) {
      playMp4(v.src);
    } else {
      playHls(v.hls).catch(function (err) {
        console.error(err);
        $desc.hidden = false;
        $desc.textContent = '视频加载失败：' + err.message;
      });
    }

    history.replaceState(null, '', '#v' + index);
  }

  function close() {
    if ($modal.hidden) return;
    teardownPlayer();
    $modal.hidden = true;
    $modal.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
    currentIndex = -1;
    history.replaceState(null, '', location.pathname + location.search);
  }

  function step(dir) {
    if (currentIndex < 0 || !videos.length) return;
    var next = (currentIndex + dir + videos.length) % videos.length;
    open(next);
  }

  /* ---------- 事件绑定 ---------- */
  $modal.addEventListener('click', function (e) {
    if (e.target.hasAttribute('data-close')) close();
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') close();
    else if (!$modal.hidden && e.key === 'ArrowRight') step(1);
    else if (!$modal.hidden && e.key === 'ArrowLeft') step(-1);
  });

  /* ---------- 启动 ---------- */
  render();

  // 支持直接用 #v3 这样的链接分享单个视频
  var m = /^#v(\d+)$/.exec(location.hash || '');
  if (m) {
    var idx = parseInt(m[1], 10);
    if (idx >= 0 && idx < videos.length) {
      // 等一拍让布局稳定
      setTimeout(function () { open(idx); }, 30);
    }
  }
})();
