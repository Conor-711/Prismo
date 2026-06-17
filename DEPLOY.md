# 部署指南

本站构建为**纯静态产物**（`web/out/`，构建期已把真实数据渲染进 HTML），零后端、可部署到任何静态托管。

> ⚠️ 为什么不在平台上直接 build：Web 端用 Node 内置 `node:sqlite` 读数据库，需要 Node 22+ 与实验 flag，多数平台默认 build 环境不满足。所以**推荐部署已构建好的 `out/`**（不在平台 build），最稳。

## 一步生成产物
```bash
make site          # = cd web && npm run build  → 产出 web/out/
```
想换最新真实数据再部署：`make real && make site`（`make real` 用 Arctic Shift 拉当天数据）。

---

## ⭐ 方式 0：本地部署（推荐 / 当前已在跑）
把静态产物部署在本机，一条命令：
```bash
make serve         # → http://localhost:8080
```
- 局域网内其他设备也可访问：`http://<你的内网IP>:8080`。
- 想长期常驻 / 开机自启：用 `pm2`、`launchd` 或 `nohup python3 -m http.server 8080 --directory web/out &`。
- 刷新数据：`make real && make site`，刷新浏览器即可。

> 想要"实时数据、免重建"的本地动态服务（改完数据直接刷新生效），也可以用 `make web-dev`（开发模式，HMR）。

---

## 方式 A：Netlify Drop（最简单，浏览器拖拽）
1. 打开 https://app.netlify.com/drop
2. 把 `web/out` 整个文件夹拖进去 → 立刻得到一个公开 URL。
（登录账号即可永久保留 / 绑定域名。）

## 方式 B：Cloudflare Pages
```bash
npx wrangler pages deploy web/out --project-name reddit-alpha
```
（首次会引导登录 Cloudflare。）

## 方式 C：Vercel（部署静态产物，不在平台 build）
```bash
cd web/out && npx vercel --prod
```
Vercel 检测到是纯静态目录，直接发布，不触发 Next build。

## 方式 D：GitHub Pages 自动部署（推荐长期方案，自动刷新数据）
已内置 workflow：`.github/workflows/deploy.yml`，在 GitHub runner 上拉真实数据(Arctic Shift)→分析→构建→发布，并**每 6 小时自动刷新**。
1. `git push` 到 GitHub（仓库需含本项目）。
2. 仓库 **Settings → Pages → Source** 选 **GitHub Actions**。
3. （可选）**Settings → Secrets → Actions** 添加 `ANTHROPIC_API_KEY`，则用真实 Claude 分析；否则用 mock 启发式。
4. 等 Action 跑完，Pages 给出公开 URL。
   - 项目页是子路径 `https://<user>.github.io/<repo>/`，workflow 已自动设 `NEXT_PUBLIC_BASE_PATH=/<repo>`。
   - 若用自定义域名 / 用户主页（根路径），把该 env 改空。

---

## 刷新数据的工作流
- 本地：`make real`（拉真实数据）→ `make site`（重建 out/）→ 重新拖到 Netlify / 重新 deploy。
- GitHub Pages：直接等定时任务，或 Actions 页面点 “Run workflow”。

## 真实 Claude 分析
默认 mock 启发式打标（情绪偏保守）。要真实 AI 分析：`.env` 填 `ANTHROPIC_API_KEY`，把 `make real` 里的 `analyze --mock / narratives --mock / brief --mock` 去掉 `--mock`（或用真实 Claude 跑 `make analyze && make narratives && make brief`）。
