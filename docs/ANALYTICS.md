# RedditAlpha 数据埋点与分析平台（Tracking Plan）

> 单一事实来源（single source of truth）。新增/变更埋点前先更新本表，避免「命名漂移」
> （同一行为被记成两个事件，指标分裂）。设计参考 Amplitude/Mixpanel 事件分类法、GA4 留存/同期群。

## 原则
- **命名**：`snake_case`，对象_动作（object_action），过去式语义。事件数量保持精简（≈10–30 个）。
- **用属性承载差异**，而不是为每个细微变体新建事件。
- **两类属性**：事件属性（这次行为的上下文）+ 用户属性（人是谁）。用户属性集中放在每会话一次的 `session_start`。
- **只统计线上真实流量**：本地/内网（localhost、私有 IP、`.local`、无点主机名）一律不记录；
  管理员本设备可一键「排除我的访问」（localStorage DNT，登录管理员自动开启）。

## 事件（event_type）
| 事件 | 触发时机 | 关键属性（meta） |
|---|---|---|
| `session_start` | 每会话首个事件前自动补发一次 | device / os / browser / vw / sw / lang / tz / channel / utm_source·medium·campaign / landing / returning / dsf / standalone |
| `pwa_install` | 安装为 App（Android / 桌面 Chrome 的 appinstalled） | — |
| `page_view` | 路由变化 | （ticker 列：个股页带标的） |
| `page_leave` | 离开/隐藏/卸载当前页 | ms（**互动时长**毫秒：仅前台+有操作累计，空闲 60s 暂停，单段封顶 30 分钟）/ clicks / maxScroll（最大滚动深度 %） |
| `ad_view` | 广告位「可见曝光」（MRC：≥50% 可见且连续 ≥1 秒、前台） | slot（广告位 id：dash_hero / dash_feed / post_body…） |
| `search` | 站内搜索提交 | q（搜索词）/ found（是否命中） |
| `share` | 点击分享/复制 | platform |
| `translate_toggle` | 切换原文/译文 | mode |

## 用户属性（session_start.meta）
- **device**：mobile / tablet / desktop（UA 分桶）
- **os / browser**：Windows·macOS·Android·iOS·Linux / Chrome·Safari·Firefox·Edge·Opera
- **channel**（获取渠道）：direct / organic / social / paid / email / referral / internal / campaign
  （由 referrer host + UTM 归类，口径近 GA4）
- **tz**：IANA 时区（≈ 粗粒度地区，隐私友好、无需 IP）
- **returning / dsf**：是否回访 / 距首访天数（`first_seen` 持久化于 localStorage）

## 聚合函数（Supabase RPC，均 `is_admin()` 门禁，仅管理员可读）
| 主题 | 函数 | 产出 |
|---|---|---|
| 触达 | `analytics_overview` / `analytics_daily` | 访客/浏览/会话/事件 + 趋势 |
| 参与度 | `analytics_engagement` / `analytics_top_paths_engaged` | 人均停留/点击/页数/跳出 + 最爱页面(停留·滚动·点击) |
| 获取 | `analytics_channels` / `analytics_traffic_sources` | 渠道构成 + UTM 活动 + 站外来源 |
| 受众画像 | `analytics_audience` | 设备/浏览器/系统/语言/时区 + 新老/回访率 |
| 活跃时段 | `analytics_hourly` | UTC+8 24 小时分布 |
| 内容意图 | `analytics_search_terms` | 站内搜索词 + 命中数（内容缺口） |
| 转化 | `analytics_funnel` | 落地→看板→个股→帖子→分享（各阶段独立访客） |
| 留存 | `analytics_retention` | N 日留存曲线 + 按获取日期的同期群三角（UTC+8） |
| 回访(周) | `analytics_returning` + `analytics_retention_weekly` | 每周新/回访活跃、回访频次、WAU/MAU 粘性、周同期群留存 |
| 变现 | `analytics_inventory` | 月页面浏览/访客/会话 + **可见曝光(ad_view)**；前端 eCPM 优先用真实可见曝光，无则回退页面浏览估算 |
| 保存 | `analytics_pwa` | 加到主屏/独立启动人数 + 安装次数（≈「存下网站」的可追踪信号） |
| 明细 | `analytics_recent` / `analytics_event_breakdown` / `analytics_top_tickers` / `analytics_lang_split` / `analytics_shares` | 事件流与分布 |

## 两大用途映射
- **产品迭代**：跳出率 + 人均停留 + 滚动深度 + 最爱页面 + 搜索词 + 漏斗 → 看「哪些页留得住人/读得深、哪里流失、用户想要什么内容」。
- **谈广告主（media kit）**：reach（独立访客）+ engagement（停留/页/点击）+ 受众构成（设备/地区/回访率/来源）→ 回答广告主三问：谁会看到、效果如何、可估 CPM。

## 迁移文件
`supabase/migrations/` 下按序执行（或连 GitHub 自动应用）：
`…_analytics.sql`（基础）→ `…_engagement.sql` → `…_admins.sql` → `…_purge_pre_launch_events.sql`
→ `…_traffic_sources_external.sql` → `…_pro_analytics.sql`（受众/渠道/时段/漏斗/搜索词/滚动）
→ `…_retention_inventory.sql`（N 日留存同期群 + 广告库存量/eCPM）。
