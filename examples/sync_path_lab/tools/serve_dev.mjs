import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const lab = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.join(lab, 'build', 'web');
const port = Number(process.argv[2] ?? 8781);
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Invalid local dev port');
const contentTypes = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
await fs.access(path.join(root, 'index.html'));
http.createServer(async (request, response) => {
  try {
    if (!['GET', 'HEAD'].includes(request.method)) { response.writeHead(405); response.end(); return; }
    const relative = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    const target = path.resolve(root, `.${relative === '/' ? '/index.html' : relative}`);
    if (!target.startsWith(`${root}${path.sep}`)) { response.writeHead(403); response.end(); return; }
    const data = await fs.readFile(target);
    response.writeHead(200, { 'Content-Type': contentTypes[path.extname(target)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(request.method === 'HEAD' ? undefined : data);
  } catch { response.writeHead(404); response.end('Not found'); }
}).listen(port, '127.0.0.1', () => console.log(`DEV game lab: http://127.0.0.1:${port}/ (only local loopback)`));
