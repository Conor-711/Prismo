# Smart Money Live Runbook

## 生产拓扑

Smart Money ingest 服务以 Hyperdash 为主源，Client API 只读取 PostgreSQL Read Model。iOS/Web 不直连 Hyperdash 或 Hyperliquid。

```bash
BSMART_ENV=production \
BSMART_SMART_MONEY_ENABLED=1 \
BSMART_SMART_MONEY_PRIMARY_SOURCE=hyperdash \
BSMART_READ_MODEL_DATABASE_URL='postgresql+psycopg://...' \
make smart-money-ingest-api
```

默认行为：

- 每 10 分钟读取一次 Hyperdash；
- 使用 `equities` 系统组和 Copy Score；
- 榜单最多 100 个账户；
- 批量获取每个账户最多 12 个当前仓位；
- 发布范围只包含 1D、7D、30D；
- 原始响应不永久堆积，只保存最后成功标准化快照和一个 Hyperliquid 降级快照。

## iOS 本地真实数据

正常 iOS Debug 不读取 fixture，而连接 `http://127.0.0.1:8081` 的统一 PostgreSQL Client API：

```bash
make x-local-up
make ios-live-unified-seed
make ios-live-smart-money
make ios-local-check
```

X worker 与 Hyperdash worker 以不同 producer 分区写入同一个 PostgreSQL Read Model：
X 观点按分钟发布，Smart Money 每 10 分钟刷新。分区发布会合并结果而不会互相覆盖。
`ios-live-seed` 与 `ios-live-api` 仅作为端口 `8085` 的历史快照降级方案。只有显式
`--use-fixture-data` 或 UI scenario 才允许 Debug fixture。

## 健康检查

`/health` 重点字段：

- `primarySource`：应为 `hyperdash`；
- `activeSource`：`hyperdash`、`hyperdash_cached`、`hyperliquid_fallback` 或 `unavailable`；
- `sourceLagSeconds`：当前对外快照年龄；
- `lastSuccessfulHyperdashAt`；
- `positionCoverage`：成功返回仓位快照的榜单账户比例；
- `readiness.ready` 和机器可读的 `readiness.reasons`。

告警建议：

| 条件 | 级别 | 处理 |
|---|---:|---|
| `activeSource != hyperdash` 持续 20 分钟 | Warning | 检查 Hyperdash 状态、出口 IP、授权和限流 |
| `sourceLagSeconds > 1800` | Critical | 数据已超过默认新鲜度，检查降级快照和 Read Model |
| `positionCoverage < 0.95` 连续 5 次 | Warning | 降低账户数或仓位数，检查 GraphQL 批量响应 |
| `/ready=503` | Critical | 当前没有可安全发布的新鲜数据 |

## 恢复

- 短暂故障：服务自动保留 `hyperdash-last-good.json`，不会让失败响应覆盖 manifest；
- Hyperdash 长期故障：确认保留的官方快照后，将 `BSMART_SMART_MONEY_PRIMARY_SOURCE` 改为 `hyperliquid` 并重启单实例服务；
- 错误发布：保留最后一份已提交 manifest，删除 `.tmp` 文件即可；
- 不要手工编辑 `smart-money*.json`，所有更新必须经过原子发布器。

## 外部依赖

当前适配器使用 Hyperdash Web 使用的公开 GraphQL 操作。上线收费产品前必须获得适当的使用许可或正式 API 方案，并确认限流、缓存和可用性条款。
