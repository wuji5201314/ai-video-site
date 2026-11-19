// 极简静态服务器（支持 Range，视频能拖进度条）
// 用法: node scripts/serve.mjs <目录> [端口] [绑定地址]
//   默认绑定 127.0.0.1；传 0.0.0.0 可让同一 WiFi 下的手机/电脑访问
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const root = process.argv[2] || '.';
const port = Number(process.argv[3] || 5173);
const host = process.argv[4] || '127.0.0.1';

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.ts': 'video/mp2t',
};

const server = createServer(async (req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  const safe = normalize(p).replace(/^(\.\.[/\\])+/, '').replace(/^[/\\]+/, '');
  const f = join(root, safe);

  let info;
  try {
    info = await stat(f);
    if (info.isDirectory()) throw new Error('dir');
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404 ' + safe);
    return;
  }

  const type = mime[extname(f).toLowerCase()] || 'application/octet-stream';

  // Range 请求：拖动进度条靠这个
  const range = req.headers.range;
  if (range && /^bytes=/.test(range)) {
    const [s, e] = range.replace('bytes=', '').split('-');
    const start = parseInt(s, 10) || 0;
    const end = e ? parseInt(e, 10) : info.size - 1;
    res.writeHead(206, {
      'Content-Type': type,
      'Content-Range': `bytes ${start}-${end}/${info.size}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': end - start + 1,
      'Cache-Control': 'no-cache',
    });
    createReadStream(f, { start, end }).pipe(res);
    return;
  }

  const buf = await readFile(f);
  res.writeHead(200, {
    'Content-Type': type,
    'Accept-Ranges': 'bytes',
    'Content-Length': buf.length,
    'Cache-Control': 'no-cache',
  });
  res.end(buf);
});

server.listen(port, host, () => {
  console.log(`serving ${root}`);
  console.log(`  http://${host === '0.0.0.0' ? '127.0.0.1' : host}:${port}/`);
  if (host === '0.0.0.0') {
    import('node:os').then(({ networkInterfaces }) => {
      for (const list of Object.values(networkInterfaces())) {
        for (const n of list || []) {
          if (n.family === 'IPv4' && !n.internal) console.log(`  http://${n.address}:${port}/  (局域网)`);
        }
      }
    });
  }
});