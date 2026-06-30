# X / Twitter 历史推文抓取需求（交给爬虫方 / AI 执行）

> 这份文档是**自包含**的：执行者不需要任何额外上下文。请严格按"硬指标 + 字段 schema + 验收清单"产出。

---

## 0. 目的（先读，它决定你所有取舍）

我们要给一批 X 账号建"**股票判断力战绩**"评分：把每条推文里对某只股票的**方向观点**抽出来，再用该股从**发推那一刻起**的后续涨跌（对标大盘/同行业）在多个固定周期（2 周 / 1 月 / 3 月 / 6 月 / 12 月）结算，按账号汇总。

由此推出对数据的几条**铁律**（违反任意一条，数据基本作废）：

1. **必须知道每条推"精确发布时间"**——我们从这个时间戳算前瞻收益。**只到"天"不行，要到秒、要 UTC。**
2. **必须有完整原文**——我们靠全文抽方向，截断（`…`）的没用。
3. **必须是某账号在窗口内的"完整"推文，不能只挑热门/只挑说对的**——否则就是幸存者偏差，整个评分被污染。哑火、说错的推**同样要**。
4. **必须够"老"**——窗口要回溯 **≥ 24 个月**，否则长周期还没结算、算不出战绩。

---

## 1. 硬指标（Definition of "够")

| 项 | 要求 |
|---|---|
| 时间深度 | 从**今天往回 ≥ 24 个月**（最低 18 个月，越长越好） |
| 时间精度 | `created_at` 必须 **秒级 + UTC**（ISO8601，如 `2024-09-12T14:03:21Z`） |
| 原文 | **完整、不截断、不清洗、不翻译**（保留 URL / emoji / 换行 / `$cashtag`） |
| 覆盖 | 目标账号在窗口内的推文要**尽量 100% 覆盖**，**不得按互动量/内容预筛** |
| 语言 | 英文为主，**中文同样要**（别只留英文）；其余语言也收，标 `lang` |
| 去重 | 以 `tweet_id` 可去重（同一条不要算两条） |

---

## 2. 抓取范围与优先级

### D1（必做：先解锁 PLTR 验证）
- **标的：PLTR（Palantir）**。匹配关键词（大小写不敏感）：`$PLTR`、独立词 `PLTR`、`Palantir`。
- **窗口：近 24 个月**。
- **要求：窗口内所有匹配推文，全账号、全语言。** 按账号**完整**收，别只收热门。
- 量级太大时的取舍：**优先保证"在窗口内发过 ≥3 条 PLTR 推"的账号被完整覆盖**；一次性提及的长尾账号尽力而为。**但绝不能用点赞/转发量当过滤器**（那会丢掉说错的人 = 幸存者偏差）。

### D2（更好：做完整产品用，可第二批）
- 取 D1 里 **PLTR 推 ≥ 5 条**的 top ~200 个账号。
- 抓这些账号**近 24 个月的全部推文（不限标的）**——我们需要他们在所有票上的完整 call 史来做难度/组合评分。

> 先交 D1 就能开工；D2 决定能不能做成正式产品。

---

## 3. 每条推文的字段 Schema

**必填（缺任一条该记录基本无效）：**

| field | 类型 | 说明 |
|---|---|---|
| `tweet_id` | string | 数字 id 转**字符串**（防整数溢出），全局唯一 |
| `author_id` | string | 账号的**稳定数字 id**（handle 会改名，去重/合并账号靠它） |
| `author_handle` | string | 用户名，不含 `@` |
| `created_at` | string | **ISO8601、UTC、秒级**，如 `2024-09-12T14:03:21Z`（命脉字段） |
| `text` | string | **完整原文**，不截断不清洗 |
| `lang` | string | 语言码（如 `en`/`zh`），非英文别丢 |
| `url` | string | 推文永久链接 |

**互动数（必填；属"抓取时快照"）：**

| field | 类型 | 说明 |
|---|---|---|
| `like_count` `retweet_count` `reply_count` `quote_count` `view_count` | int \| null | 拿不到填 null，别瞎填 0 |
| `crawled_at` | string | 抓这些计数的时刻（ISO8601 UTC）——因为互动是快照 |

**结构标记（能判定就填，用于区分原创/转推/回复/引用）：**

| field | 类型 | 说明 |
|---|---|---|
| `is_retweet` | bool | 纯转推（`RT @…`）必须能识别（我们会剔除纯 RT） |
| `retweeted_tweet_id` / `retweeted_handle` | string \| null | 若是转推 |
| `is_reply` | bool | 观点常出现在回复里，回复**要收** |
| `in_reply_to_tweet_id` / `in_reply_to_handle` | string \| null | |
| `is_quote` | bool | |
| `quoted_tweet_id` / `quoted_text` | string \| null | 引用推的**原文也要**（上下文） |
| `conversation_id` | string | 线程 id，便于拼 thread |

**选填（有最好，没有不阻塞）：** `author_name`、`author_followers`(快照)、`author_verified`、`author_created_at`、`has_media`(bool)、`media_types`(array)、`cashtags`(array，你识别到的 `$TICKER`；我们也会自己再抽)。

---

## 4. 输出格式与交付

- **格式：JSONL**（一行一个 JSON 对象），UTF-8、无 BOM。
- 文件命名：`pltr_tweets_<起>_<止>.jsonl`（D2 用 `account_<handle>_all_<起>_<止>.jsonl`）。大文件可按月/按账号分片。
- 只有无法产出 JSONL 时才用 CSV，且必须正确转义、嵌套字段拍平、`text` 完整。
- 交付方式不限（你把文件给我即可）。**别在导出时做任何"清洗/去噪/筛选"。**

---

## 5. 样例记录（一行）

```json
{"tweet_id":"1834012345678901234","author_id":"44196397","author_handle":"someinvestor","author_name":"Some Investor","created_at":"2024-09-12T14:03:21Z","text":"$PLTR at $28 is the cheapest it'll ever be. AIP demand is inflecting hard. Adding aggressively, target $45 by year-end.","lang":"en","url":"https://x.com/someinvestor/status/1834012345678901234","like_count":312,"retweet_count":41,"reply_count":58,"quote_count":7,"view_count":51000,"crawled_at":"2026-06-26T09:00:00Z","is_retweet":false,"is_reply":false,"is_quote":false,"in_reply_to_tweet_id":null,"retweeted_tweet_id":null,"quoted_tweet_id":null,"conversation_id":"1834012345678901234","author_followers":18400,"author_verified":true,"cashtags":["PLTR"]}
```

---

## 6. 验收清单（Definition of Done）

- [ ] 时间跨度 ≥ 24 个月（最老一条 ≤ 今天减 24 个月）。
- [ ] 每条都有 7 个必填字段，尤其 `created_at`（秒级 UTC）+ `text`（完整）。
- [ ] PLTR：窗口内匹配推文按账号完整覆盖，**没有按互动量/内容预筛**。
- [ ] 回复 / 引用推也收了；纯转推可识别。
- [ ] `tweet_id` 可去重；中文等非英文未被丢弃。
- [ ] JSONL、UTF-8、原文未截断未清洗。

---

## 7. 千万别做（这些会让数据白抓）

- ❌ 时间戳只到"天"或本地时区 —— 必须秒级 UTC。
- ❌ 截断正文 / 去掉 URL / 翻译 / "清洗噪音"。
- ❌ 只保留高赞高转的推（= 幸存者偏差，丢了"说错的人"）。
- ❌ 只抓近期（7 天 / 1 个月）—— 必须回溯 ≥ 24 个月。
- ❌ 丢掉回复和引用推（观点常在里面）。
- ❌ 用 `handle` 当账号唯一键（会改名）—— 用 `author_id`。
```
