# 官方信息：从作者判断回到公司披露

状态：历史研究与交互原型，研究日期 2026-09-08。2026-09-09 的用户决策和代码实现以 [观点相关依据](opinion-supporting-sources.md) 为准：不限官方来源、不开发渠道追踪、没有依据时隐藏整个模块。本页下文保留当时调研过程，不再作为开发需求；其中的官方频道、缺失提示与订阅对象均不实施。

原型：[official-context/index.html](prototypes/official-context/index.html)。直接打开即可，无须启动服务。

## 1. 需求判断

这个需求值得做，但应定位为观点的上下文补全，而不是“新增财经新闻功能”。

用户的工作是：看到一个值得关注的人的判断后，用很低的成本知道，他涉及的那件官方消息到底是什么，以及后续有没有更新。它服务半主动投资者，不要求用户读完财报、复核模型或完成研究任务。

建议界面名称：**官方信息 / Official Context**。底层对象称 OfficialEvent。官方身份只描述发布主体，不保证事实绝对正确、预测会兑现或作者结论正确；公司新闻稿本身可能包含营销及前瞻性陈述。页面使用“公司披露”“管理层预期”“作者推断”分别表达。

不改变以标的为外层、主体与判断为内容的现有方向，也不改变 Score / Smart Consensus / Smart Alpha 的评分、入选或收益计算。新增来源不能自动加分。

## 2. 市场参照

以下为公开官方产品文档调研，不是登录后的完整 App 实测。未发现可依据这些文档认定与 bSmart 需求完全相同的“投资博主观点自动关联官方段落”方案；下表为可借鉴的相邻机制。

| 产品 | 已公开说明的机制 | bSmart 借鉴 | 不照搬 |
|---|---|---|---|
| Quartr | 公司一手 IR 材料、关注与通知；关键词可定位转录语句 | 按公司追踪官方渠道；出处直达相关位置 | 大型财报研究工作台 |
| Particle | Story 组织报道、引语、原始资源链接及相关背景；追踪实体 | 将同一事件的多个材料聚为一件事 | 全市场新闻 Feed |
| AlphaSense | 摘要含直接引用，点击打开原文并高亮段落 | 具体声称与具体段落一一对应 | 将长篇 AI 报告加入每条观点 |
| Koyfin | Watchlist News 按自选组织新闻、公告、filings 与 transcripts；提供文件提醒 | 范围与类型过滤，沿用持仓/关注体系 | 把所有公告都即时推送 |

来源：[Quartr 移动端](https://quartr.com/products/mobile-app)、[Quartr 关键词提醒](https://quartr.com/features/keyword-alerts)、[Particle 官方介绍](https://particle.news/blog/introducing-particle-the-news-organized)、[AlphaSense 引用交互](https://help.alpha-sense.com/hc/en-us/articles/41666587181203-Interacting-with-Generative-Search)、[Koyfin Watchlist News](https://www.koyfin.com/help/watchlist-news-feature/)、[Koyfin 文件提醒](https://www.koyfin.com/help/release-notes/v3-66-desktop-alerts/)。

以上不能证明用户一定需要或愿意付费；它们只证明一手资料追踪、上下文组织、段落引用已有成熟产品机制。bSmart 的价值假设仍需试点验证。

## 3. 页面与交互

### 观点详情

- 放在作者原文/译文之后、长图表及历史表现之前，不埋在最底部。
- 正文下默认呈现 1 件最相关披露；确有多个独立事件时最多 2 件，更多进入完整资料页。
- 卡片显示：发布主体和 logo、类型、事实性标题、至多两行转述、原始发布日期、财季、关系类型。
- 顶部可用“1 件官方披露”锚点定位模块；不改变作者原文，用展示层引用关联，绝不改写原帖链接。
- 卡片打开独立详情页，用项目已有共享元素放大转场，返回保留滚动位置。不是底部抽屉。
- 卡片下方“追踪 NVIDIA 官方”，与关注作者、收藏标的独立。

### 官方披露详情

- 首屏展示公司、具体事件、完整发布日期与财季。不要把 FY2026 错写为自然年 2026。
- 只转述与本观点有关的 1–3 个官方信息点。数字保留币种、单位、同比/环比、GAAP/non-GAAP 与对应期间。
- 已公布业绩与管理层指引分区；“签署意向”与“已签合同/已交付”保留原文状态。
- 每项转述绑定可定位段落；提供必要短摘录、中文转述与打开官方原文，不把机器转述标成原文。
- 明确推断边界，例如合作公告不含订单金额，不能从合作推断确定收入。
- 原文与 SEC 附件属于同一事件的多个文件，不宣称多份副本构成多源独立验证。
- 底部可返回原作者观点；不在第一版引入复杂“所有作者对该事件的解读榜”。

### 公司官方渠道

- 层级：标的详情下的子页，无独立主 Tab。
- 按公司实体订阅一组经过确认的来源：IR、Newsroom 和该发行人的 SEC 披露；不让用户管理 RSS URL。
- 官方发布时间倒序，类型筛选。默认先覆盖财报及重大合作/公司公告，排除活动预告、例行表格等噪声。
- 追踪不改变持仓、标的收藏或作者关注；在现有追踪与提醒设置中增加“官方渠道”类别。
- 默认每日摘要，用户可明确开启“重要披露即时，其余进摘要”。纯设置预览不申请系统通知权限；真正启用即时提醒时再请求。
- 官方披露可以独立触发该频道更新，不必等待博主谈论它。但不因此重排 Today 主结构。
- 若同一事件同时触发作者与官方提醒，发送一次合并通知，进入来源分别标注的落地页。

## 4. 什么能叫引用

| 关系 | 证据 | UI |
|---|---|---|
| explicit_citation | 原帖链接经跳转确认属于官方文件，且内容相关；或可精确定位的官方引文 | 作者引用 |
| related_context | 没有明确引用，系统检索到实体、事件、时间与具体事实匹配的材料 | 相关官方资料 · 系统关联 |
| later_update | 披露发生在作者发帖之后 | 后续官方更新，不作为发帖时依据 |
| unresolved | 仅传闻、对象/财季不明、全文不可取或匹配不足 | 不生成摘要；明确事实声称才展示简短缺失状态 |

纯技术分析、情绪或个人预测没有官方来源是正常状态，不在每条观点下强行放空模块。不得仅凭同 ticker 或最新日期关联；不能把合作方公告当成该公司自身声明，也不能根据蓝勾判断官方身份。

## 5. 数据与发布链路

第一版试点建议 10 个已有高质量观点的主要标的，先做明确引用与人工审核，通过后逐步开放语义关联。

1. SourceRegistry 维护公司实体、ticker 别名/CIK、允许域名及具体栏目。官方托管 CDN 需由官网链接确认；合作方域名按其自身身份展示。
2. 优先接入 IR RSS/API、Newsroom 发布源与 SEC 提交记录；遵守各站访问规则、许可与限流。NVIDIA 已提供 [RSS](https://investor.nvidia.com/investor-resources/rss/default.aspx) 与 [邮件提醒](https://investor.nvidia.com/investor-resources/email-alerts/default.aspx)。SEC 提供 [开发者资源](https://www.sec.gov/about/developer-resources)，其访问上限不等于应持续打满的抓取速率。
3. URL 归一化、跳转校验、原文抓取、文档版本/哈希存储。作者提供的 URL 属不可信输入：防 SSRF，阻止内网地址和危险协议，网页内容不得成为模型指令。
4. 识别观点中的具体声称，按显式链接优先、实体+事件+财季/日期检索候选；语义相似只用于召回，不能作为最终发布依据。
5. 独立校验发布时间、单位与数值、业务实体、文本支持关系，再生成有限摘要。每条摘要必须绑定 passage；无法核实时弃权。
6. 以 OfficialEvent 去重，同事件文件及版本聚合。保留关系生成时间、原发布时间和后续更新时间，不用抓取时间重排成新事件。
7. 观点本身可按原有流程 ready，不等待新模块；官方模块独立 pending/ready/unavailable，ready 后可补充，但不重复发送原观点通知。

规划对象（本轮不改现有 API/数据库）：

- OfficialEvent：issuerId、tickers、eventType、fiscalPeriod、eventDate、firstPublishedAt、updatedAt、canonicalDocumentId。
- OfficialDocument：publisherId、canonicalUrl、sourceKind、publishedAt、retrievedAt、revision、contentHash、status、passages。
- OpinionSourceLink：opinionId、claimSpan、eventId、documentRevision、passageIds、relation、matchedAt、reviewState。
- DisclosureSummary：factPoints、forwardLookingPoints、sourcePassageIds、language、generationVersion。
- OfficialSubscription：userId、issuerId、eventTypes、deliveryPreference。

历史视角固定使用当时存在的文件版本；更正后保留旧关系与“已更正”提示。被撤回的事实停止展示，既有推送不能消失但应能进入更正说明。无法访问原文时不继续声称“已验证”。

公开可读不等于可全文再分发：MVP 使用客观短转述、必要短摘录与原文入口，按来源确认许可，不复制媒体付费全文。

## 6. 验收与上线顺序

- 先离线标注样本集，覆盖真实直接引用、未给链接、相似但不同事件、旧财季、合作方、多标的、传闻、更正与晚发公告。
- 分开测“来源确为官方”“资料与声称匹配”“摘要忠实”。发布精度优先于覆盖率；建议试点精度门槛 98%，这是待验证的产品目标而非当前指标。
- 数字与时期逐项精确核对，预测误写为已实现、后发材料冒充原引用、错误公司归属作为阻断缺陷。
- UX 看卡片展开、原文点击、官方渠道追踪、每周阅读、用户反馈与退订；不把浏览时长或新闻数量设为成功标准。
- 分两步上线：先详情中的官方信息，再官方渠道追踪/提醒；不同时建设完整财务数据终端。

## 7. 原型数据边界

作者、排名和观点均为明确标识的交互样例，不冒用真实博主发言。两件官方材料均为真实历史资料：

- [NVIDIA FY2026 Q2 业绩，2025-08-27](https://nvidianews.nvidia.com/news/nvidia-announces-financial-results-for-second-quarter-fiscal-2026)
- [Oracle / NVIDIA 企业 AI 合作，2025-03-18](https://nvidianews.nvidia.com/news/oracle-and-nvidia-collaborate-to-help-enterprises-accelerate-agentic-ai-inference)

原型演示卡片到独立详情的共享元素转场、逐项原文摘录、官方原文链接、返回保留位置、公司渠道、类型筛选、追踪/取消及本地设置。它不采集新公告、不发送真实提醒、不下单。本轮不修改 SwiftUI、排名或生产管线。
