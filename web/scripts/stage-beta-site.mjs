import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const source = fileURLToPath(new URL("../out/", import.meta.url));
const destination = "/tmp/bsmart-beta-out-cf";
const assets = [
  "index.html", "index.txt", "zh/index.html", "zh/index.txt", "en/index.html", "en/index.txt",
  "404.html", "_next", "_routes.json", "sw.js", "icon.png", "icon-192.png", "icon-512.png",
  "brand/bsmart-wordmark-beta.png", "brand/bsmart-wordmark.png", "favicon.ico", "apple-touch-icon.png",
  "brand/market-editorial-annie-spratt.jpg",
];

// Only clear this script's dedicated staging directory, never the complete static export.
await rm(destination, { recursive: true, force: true });
for (const asset of assets) {
  const target = join(destination, asset);
  await mkdir(dirname(target), { recursive: true });
  await cp(join(source, asset), target, { recursive: true });
}
const manifest = JSON.parse(await readFile(join(source, "manifest.webmanifest"), "utf8"));
Object.assign(manifest, {
  name: "bSmart", description: "关注值得听的市场声音。申请 bSmart 内测。",
  background_color: "#f8f8f5", theme_color: "#f8f8f5",
});
await writeFile(join(destination, "manifest.webmanifest"), JSON.stringify(manifest));
await writeFile(join(destination, "robots.txt"), "User-agent: *\nAllow: /\nDisallow: /api/\nSitemap: https://bsmart.today/sitemap.xml\n");
await writeFile(join(destination, "sitemap.xml"), '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' +
  ["/", "/zh/", "/en/"].map(path => `<url><loc>https://bsmart.today${path}</loc></url>`).join("") + "</urlset>\n");
console.log(`Beta site staged: ${destination}`);
