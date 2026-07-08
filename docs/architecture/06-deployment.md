# Deployment Architecture

Prismo 的推荐部署路径是静态构建加内容快照。线上页面应该等价于本地 `data/dev.db` 构建结果。

## 推荐路径

1. 本地管线写入 `data/dev.db`。
2. 本地执行 `make site` 生成 `web/out/`。
3. 使用 Cloudflare Pages Direct Upload 部署静态产物。

这种方式避免线上构建环境重新抓取、重新分析或缺少 LFS 数据导致页面为空。

## 数据快照

- `data/dev.db` 是内容真源。
- `data/dev.db.xz.part-*` 和 `data/dev.db.xz.parts` 是部署友好的普通 Git 分片快照。
- 改数据前应先备份。
- 不应使用只含 Reddit 核心表的 cloud-pull 覆盖 Prismo 本地真源。

## Railway / Docker

Railway/Docker 仍可作为备用路径，但必须确保构建上下文中能还原完整 `data/dev.db`。

Docker 构建规则：

- 优先用 `data/dev.db.xz.parts` 拼接分片。
- 没有分片 manifest 时才回退旧快照。
- 构建期仍由 Next.js 读取本地 sqlite。

## 验证

部署前至少检查：

- `data/dev.db` 存在且大小合理。
- `make site` 成功。
- `web/out/zh/tickers/<SYMBOL>/index.html` 能生成。
- 关键数据页面不显示“暂无数据”。
- 线上部署没有重新执行 cloud-pull。
