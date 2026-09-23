# Deployment Architecture

Telegram 频道的 X 文件接收不是云端常驻服务：小于 20 MB 的文件默认由公共 Bot API 下载；超过该限额时，`deploy/telegram-bot-api/docker-compose.yml` 可在本机以 localhost:8081 运行 Local Bot API，持久化缓存到忽略 Git 的 `data/runtime/telegram-bot-api`。`make content-delivery` 在本机三小时任务中调用接收与发布队列；本机离线时不保证时效，使用本地服务时 Docker 停止也会中断。普通模式只需 Bot Token 和频道授权，大文件模式另需 API ID/Hash；切到本地服务前运行 `telegram-bot-api-cutover`。自动下载的本地原件只在数据库验证发布后清理；参见 `docs/operations/telegram-x-delivery.md`。

bSmart 的推荐部署路径是静态构建加内容快照。线上页面应该等价于本地 `data/dev.db` 构建结果。

## 推荐路径

1. 本地管线写入 `data/dev.db`。
2. 改数据前执行 `make backup-db`，备份写到项目外且默认只保留最近一份。
3. 本地执行 `make site` 生成 `web/out/`。
4. 使用 Cloudflare Pages Direct Upload 部署静态产物。

### bsmart.today 内测官网

`make cf-deploy` 使用完整 `make site` 后的产物，由 `web/scripts/stage-beta-site.mjs` 抽取 `/`、`/zh/`、`/en/` 和必要资源到 `/tmp/bsmart-beta-out-cf`。研究页和 `/data` 留在 `web/out`，不发布到单页官网。官网专用 manifest、robots 和 sitemap 在抽取时生成。

部署从 `web/` 调用 Wrangler 4.131.1，以同时上传 `web/functions`；生产 Pages 项目为 `bsmart`，实际默认域名为 `bsmart-501.pages.dev`，`WAITLIST` 绑定独立生产 KV。网站、邮箱持久化和正式域名分别验收，不能互相替代；当前域名接入状态见 `docs/operations/beta-landing.md`。

这种方式避免线上构建环境重新抓取、重新分析或缺少 LFS 数据导致页面为空。

## 数据快照

- `data/dev.db` 是本地内容真源，但被 `.gitignore` 忽略，不能直接提交。
- `make snapshot-db` 先生成一致、紧凑的 SQLite 快照，再压缩并完整校验。
- 快照优先使用系统 `xz` 多线程压缩；没有 `xz` 时回退 Python `lzma`，产物格式与校验口径相同。
- 压缩结果不超过 90MB 时只保留 `data/dev.db.xz`；超过时只保留
  `data/dev.db.xz.part-*` 和 `data/dev.db.xz.parts`，避免重复副本。
- `make backup-db` 使用 SQLite backup API 写到项目外，默认只保留最近一份。
- 不应使用只含 Reddit 核心表的 cloud-pull 覆盖 bSmart 本地真源。

## Railway / Docker

Railway/Docker 仍可作为备用路径，但必须确保构建上下文中能还原完整 `data/dev.db`。

Docker 构建规则：

- 优先用 `data/dev.db.xz.parts` 拼接分片。
- 没有分片 manifest 时使用单文件 `data/dev.db.xz`。
- 原始 `data/dev.db` 不进入 Docker build context 的数据来源。
- 构建期仍由 Next.js 读取本地 sqlite。

## 验证

部署前至少检查：

- 本地 `data/dev.db` 存在且 `PRAGMA quick_check` 通过。
- 发布到 Railway 前执行 `make snapshot-db` 并提交生成的快照与 metadata。
- `make site` 成功。
- `web/out/zh/tickers/<SYMBOL>/index.html` 能生成。
- 关键数据页面不显示“暂无数据”。
- 线上部署没有重新执行 cloud-pull。

标的详情的大体积数据使用 `/data/<dataset>/<SYMBOL>` 静态文件。客户端必须通过
`web/lib/site.ts` 的 `staticDataUrl()` 生成地址：开发模式追加末尾斜杠以匹配
Next 路由，生产静态导出不追加末尾斜杠，以匹配 Cloudflare 上的实际文件。
