/* =========================================================================
 *  你只需要改这个文件，就能增删视频。
 *  ---------------------------------------------------------------------
 *  一条视频的字段：
 *    title    （必填）标题
 *    src      （二选一）直接可播的文件，例如 "media/我的视频.mp4"
 *    hls      （二选一）m3u8 播放列表，例如 "hls/demo/index.m3u8"
 *             —— 视频超过 100MB 时用这个，脚本会自动切片
 *    poster   （可选）封面图，例如 "media/我的视频.jpg"
 *    desc     （可选）简介
 *    date     （可选）日期，例如 "2026-11"
 *    portrait （可选）竖屏视频写 true，卡片画框会变成 3:4
 *
 *  规则：src 和 hls 至少写一个。两个都写时优先用 src。
 *  路径都是相对 index.html 的位置，不要以 / 开头。
 * ========================================================================= */

window.SITE = {
  title: 'AI 视频作品集',
  subtitle: 'AI 生成 · 在线观看',
  footer: 'Made with AI'
};

window.VIDEOS = [
  {
    title: 'AURORA RUBY · 20s 电影感广告',
    src: 'media/aurora-ruby.mp4',
    poster: 'media/aurora-ruby.jpg',
    desc: '20 秒竖屏 AI 广告片，1080p。原始 35.8MB，转码后 4.2MB。',
    date: '2026-11',
    portrait: true
  },

  {
    title: '洁面真人推广 · 20s 成片',
    src: 'media/cleanser-ad.mp4',
    poster: 'media/cleanser-ad.jpg',
    desc: '20 秒，原片 1080x1920',
    date: '2026-11',
    portrait: true
  },

  {
    title: '山野徒步 · 30s 户外真人',
    src: 'media/hiking-outdoor-30s.mp4',
    poster: 'media/hiking-outdoor-30s.jpg',
    desc: '30 秒，540x960 竖屏，户外徒步场景',
    date: '2026-11',
    portrait: true
  },

  {
    title: '调研 → 成稿 → 审核 · 10s 口播',
    src: 'media/office-pitch-10s.mp4',
    poster: 'media/office-pitch-10s.jpg',
    desc: '10 秒，720x1280 竖屏，办公室口播',
    date: '2026-11',
    portrait: true
  },

  {
    title: '清晨醒来 · 30s 生活场景',
    src: 'media/morning-wake-30s.mp4',
    poster: 'media/morning-wake-30s.jpg',
    desc: '30 秒，720x1280 竖屏，晨光卧室',
    date: '2026-11',
    portrait: true
  },

  {
    title: '每期跑通一个能用的工具 · 2分27秒',
    src: 'media/tool-tutorial-2m.mp4',
    poster: 'media/tool-tutorial-2m.jpg',
    desc: '横屏 960x544，工具教程口播，2 分 27 秒',
    date: '2026-11'
  }

  // ====== 模板：复制一段改文件名即可 ======
  //
  // {
  //   title: '第二个短片',
  //   src: 'media/demo2.mp4',
  //   poster: 'media/demo2.jpg',
  //   desc: '用 XX 模型生成，12 秒，1080p。',
  //   date: '2026-11'
  // },
  //
  // {
  //   title: '大文件走 HLS',
  //   hls: 'hls/demo3/index.m3u8',
  //   poster: 'media/demo3.jpg',
  //   desc: '原始文件 400MB，切片后每片 4MB。'
  // }
];

// 下面这段别删：老浏览器兜底
if (typeof window.VIDEOS === 'undefined') window.VIDEOS = [];