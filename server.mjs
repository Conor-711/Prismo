// 生产静态服务：托管 Next 静态导出（web/out）。读 process.env.PORT，
// 不依赖任何 shell 展开（修复 Railway 把 ${PORT} 当字面量传参的问题）。
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { join, normalize, extname } from "node:path";

const ROOT = join(process.cwd(), "web", "out");
const PORT = parseInt(process.env.PORT || "8080", 10);

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".map": "application/json",
};

async function resolveFile(p) {
  try {
    const s = await stat(p);
    if (s.isFile()) return p;
    if (s.isDirectory()) {
      const idx = join(p, "index.html");
      if ((await stat(idx)).isFile()) return idx;
    }
  } catch {}
  try {
    const html = p + ".html"; // 支持非 trailingSlash 访问
    if ((await stat(html)).isFile()) return html;
  } catch {}
  return null;
}

const server = createServer(async (req, res) => {
  try {
    const path = decodeURIComponent((req.url || "/").split("?")[0]);
    let target = normalize(join(ROOT, path));
    if (!target.startsWith(ROOT)) {
      res.writeHead(403);
      return res.end("Forbidden");
    }
    let file = await resolveFile(target);
    let status = 200;
    if (!file) {
      file = join(ROOT, "404.html");
      status = 404;
      try {
        await stat(file);
      } catch {
        res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
        return res.end("Not found");
      }
    }
    const type = TYPES[extname(file).toLowerCase()] || "application/octet-stream";
    const cache = file.includes("/_next/") ? "public, max-age=31536000, immutable" : "public, max-age=300";
    if (req.method === "HEAD") {
      res.writeHead(status, { "content-type": type, "cache-control": cache });
      return res.end();
    }
    const body = await readFile(file);
    res.writeHead(status, { "content-type": type, "cache-control": cache });
    res.end(body);
  } catch (e) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end("Server error");
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`redditalpha static server listening on 0.0.0.0:${PORT} (root: ${ROOT})`);
});
