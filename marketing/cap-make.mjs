import fs from "node:fs";
const h = fs.readFileSync("marketing/redditalpha-launch.html", "utf8");
const css = h.slice(h.indexOf("<style>") + 7, h.indexOf("</style>"));
const stage = h.slice(h.indexOf('<div id="stageWrap">'), h.indexOf("<audio"));
const driver = fs.readFileSync("marketing/cap-driver.js", "utf8");
fs.mkdirSync("marketing/remotion/cap", { recursive: true });
const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@700;800;900&display=swap" rel="stylesheet">
<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js"></script>
<style>${css}
#bar{display:none!important}
html,body{margin:0;background:#e7ecf0;overflow:hidden}
#stageWrap{position:absolute!important;inset:0!important;margin:0!important}
#stage{position:absolute!important;top:0!important;left:0!important;width:1280px!important;height:720px!important;transform:none!important;border-radius:0!important;box-shadow:none!important}
.bob{animation:none!important}
</style></head><body>
${stage}
<script>${driver}</script>
</body></html>`;
fs.writeFileSync("marketing/remotion/cap/capture.html", html);
console.log("capture.html", Math.round(html.length / 1024), "KB");
