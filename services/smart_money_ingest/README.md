# Smart Money Ingest Service

单实例生产服务。默认每 10 分钟读取 Hyperdash 的 `Equities Focused` 30 天账户榜和当前仓位快照，将 Hyperdash Copy Score 原样映射到现有 Smart Money API，并原子发布到 PostgreSQL Read Model。

生产必需配置：

- `BSMART_ENV=production`
- `BSMART_SMART_MONEY_ENABLED=1`
- `BSMART_SMART_MONEY_PRIMARY_SOURCE=hyperdash`
- `BSMART_SMART_MONEY_DATA_DIR=/data`
- `BSMART_READ_MODEL_DATABASE_URL=postgresql+psycopg://...`

可选 Hyperdash 配置见 `.env.example`。获得正式 API 或商业授权后，可通过 `BSMART_HYPERDASH_AUTHORIZATION` / `BSMART_HYPERDASH_COOKIE` 注入会话，不需要修改适配器。

服务只运行一个 Uvicorn worker。`/health` 返回 `primarySource`、`activeSource`、来源延迟、仓位覆盖率和最后错误；`/ready` 只在主源或允许的新鲜缓存/降级快照可用时返回 200。

设置 `BSMART_SMART_MONEY_PRIMARY_SOURCE=hyperliquid` 可显式恢复官方 Hyperliquid 自建管线，用于诊断或第三方长期不可用时的应急模式。完整运行说明见 `docs/operations/smart-money-live.md`。
