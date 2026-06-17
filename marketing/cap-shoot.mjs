import puppeteer from "puppeteer-core";
import fs from "node:fs";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const FPS = 30;
const N = 627; // ~20.9s
const test = process.argv.includes("--test");
const outDir = test ? "marketing/remotion/cap/test" : "marketing/remotion/cap/frames";
fs.mkdirSync(outDir, { recursive: true });

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: "new",
  args: ["--no-sandbox", "--force-color-profile=srgb", "--hide-scrollbars"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720, deviceScaleFactor: 1.5 });
await page.goto("file://" + process.cwd() + "/marketing/remotion/cap/capture.html", { waitUntil: "networkidle0" });
await page.waitForFunction("window.__ready===true", { timeout: 30000 });
await page.evaluate(() => (document.fonts ? document.fonts.ready : Promise.resolve()));

const clip = { x: 0, y: 0, width: 1280, height: 720 };
const frames = test ? [0, 90, 150, 300, 360, 450, 545, 600] : Array.from({ length: N }, (_, i) => i);
let done = 0;
for (const i of frames) {
  await page.evaluate((t) => window.__seek(t), i / FPS);
  await page.screenshot({ path: outDir + "/" + String(i).padStart(4, "0") + ".png", clip });
  if (++done % 60 === 0) console.log("  ", done, "/", frames.length);
}
await browser.close();
console.log("captured", frames.length, "frames ->", outDir);
