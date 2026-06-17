/* redditalpha Service Worker —— 保守策略，避免「内容陈旧」：
 *  • 静态资源（/_next/static、字体、图片，文件名带 hash）→ cache-first（永不变）
 *  • 导航/HTML → network-first（始终拿最新内容），离线时回退缓存或首页
 *  站点每日更新，故 HTML 绝不长期缓存。bump CACHE 版本即可整体失效。 */
const CACHE = "ra-v1";
const ASSET_RE = /\/_next\/static\/|\.(?:css|js|woff2?|ttf|png|jpe?g|svg|webp|gif|ico)$/i;

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (e) => {
  e.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
      await self.clients.claim();
    })()
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  let url;
  try {
    url = new URL(req.url);
  } catch {
    return;
  }
  if (url.origin !== self.location.origin) return; // 第三方（Supabase 等）不拦截

  if (ASSET_RE.test(url.pathname)) {
    e.respondWith(cacheFirst(req));
  } else if (req.mode === "navigate") {
    e.respondWith(networkFirst(req));
  }
});

async function cacheFirst(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req);
  if (hit) return hit;
  try {
    const res = await fetch(req);
    if (res && res.ok) cache.put(req, res.clone());
    return res;
  } catch {
    return hit || Response.error();
  }
}

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  try {
    const res = await fetch(req);
    if (res && res.ok) cache.put(req, res.clone());
    return res;
  } catch {
    return (
      (await cache.match(req)) ||
      (await cache.match("/")) ||
      new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain; charset=utf-8" } })
    );
  }
}
