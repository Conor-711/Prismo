# 观点相关依据

确认及实现日期：2026-09-09。替代 `official-context-proposal.md` 的功能范围。

## 产品边界

帮助用户理解作者提到的事实是什么、材料说了什么。不是新闻首页、事实评分器或新的追踪系统。

- 名称：相关依据 / Supporting sources。
- 覆盖：公司公告、财报、合作、监管文件、媒体报道、研究报告、数据发布等可定位资料，不限官方。
- 不新增官方渠道追踪、订阅、推送、主导航或交易动作。
- 无匹配、尚未审核、撤回、字段不完整时，不显示标题、卡片或缺失提示；原观点照常显示。
- 技术分析和主观判断不要求附带材料。不得以有无该模块改变 Smart Account 排名或提示可信/不可信。
- 资料只对应具体事实，不为作者的目标价、操作建议或全部结论背书。

## 原生页面

观点详情的原文/译文之后展示最多两条卡片，更多资料打开独立列表。每条显示发布主体、类型、标的、事实标题、短摘要、发布日期和关系。

卡片以现有共享元素转场打开依据详情，返回保留上页位置，详情仍隐藏主 Tab。内容依次为发布主体、标题、日期、资料摘要、观点中的对应表述、原文短摘录及段落名称、必要的适用边界、原文链接。没有“追踪官方”按钮。

关系明确分为：

| 关系 | 使用条件 |
|---|---|
| 作者引用 | 已核对作者明确引用，不因相关性而自动认定 |
| 相关资料 | 系统关联到同一事实，但没有确认作者使用过该材料 |
| 后续资料 | 发布或当前版本更新晚于观点，不作为作者当时已有的依据 |

保留源文摘录，摘要与原文分层，支持中英文。仅有日期的材料按源日期展示，不因用户时区变成下一天。标注发布者的实际身份，例如 AWS 公告不是 NVIDIA 声明，发行人 SEC 申报不是 SEC 对投资判断的认可。

## 已实现链路

1. 人工核对真实材料，录入 `pipeline/domain/opinions/data/supporting_sources.json`。
2. 按平台、作者 ID、原帖 ID、标的精确匹配，并校验对应表述确实存在于完整原帖；仅同标的不能匹配。
3. 校验类型、审核状态、来源 URL、发布时间、关系和必要字段；去重，撤回时删除附件，不改原观点。
4. 批量 Smart Account 导出和 X realtime 发布任务在投影生成阶段补充 `supportingSources`。
5. 现有 API 原样发布、缓存、返回可选字段。iOS 模型再次过滤不可展示项。

没有修改数据库 schema、Score、Call 抽取、收益结算或提醒幂等规则。关联资料不触发重复观点提醒。API 不依赖 pipeline，不在读请求中发起网络检索。

首批从现有真实历史观点接入两个样本：WallStTitan 的 NVDA / AWS 扩容观点，以及 Mark Hogan 的 NBIS / Microsoft 合同观点。文件中的日期、摘要及短摘录已核对相应 AWS 原文和 SEC 文件。它们是相关资料，不冒充作者明确引用。

已增加下述小批量公开网页抓取实验；通用全网搜索、语义匹配及审核工具仍未实现。不承诺所有新帖自动取得依据，也没有把假数据补进未知观点。

## 本地抓取实验

按本轮要求，只对目前本地快照中的 4 条观点补充 5 条真实材料，不运行全量任务：

| 作者 / 标的 | 关联材料 | 关系 |
|---|---|---|
| Jonah Lupton / NVDA | 美联社财报报道，对应收入增速表述 | 后续资料，当前报道版本在观点之后更新 |
| James Woolley / NVDA | 同一美联社报道，对应财报事件 | 后续资料，财报结果晚于盘前观点 |
| Daniel Koss / NBIS | Nebius 可转债定价公告、融资完成公告 | 两条后续资料；同一次融资，不算两次独立确认 |
| Nate Endicott / NBIS | Nebius 对 Tavily 收购及整合的说明 | 相关资料，不为作者的投资判断背书 |

Ben Lam 的一条技术分析观点作为无关联对照，仍无资料模块。原 WallStTitan / Mark Hogan 两条历史样本保留。

入口为 `pipeline.jobs.opinion_source_crawl`。平台抓取适配器位于 `pipeline/platforms/source_documents`；事实匹配规则位于 `pipeline/domain/opinions/crawled_sources.py`，job 只编排。`local_crawl_samples.json` 明确指定观点、文章候选、标题、关键事实与短摘录；从 newsroom 索引发现链接，较老文章保留直接链接作为备选。标题与双语摘要为人工核对的样本配置，程序自动抓取正文和日期、核验匹配并关联，不冒充通用 AI 自动研究。

读取公开 HTML，遵守 robots；单主机最低间隔 1 秒，单页上限 2 MB，每次默认最多 30 个请求，缓存 24 小时。403、429、超时、禁止抓取、事实不匹配及日期不明均跳过；不绕过登录、验证码或付费墙。只发布短摘录，不把全文打包进 App。运行不需要模型或付费搜索接口。公开可访问不等于商业再分发授权，扩大覆盖前仍需核对来源许可。

```sh
# 只抓取、核验，报告写入已忽略的 data/runtime/opinion-source-crawl
pipeline/.venv/bin/python -m pipeline.jobs.opinion_source_crawl

# 写入独立抓取目录并更新当前/历史本地观点数据
pipeline/.venv/bin/python -m pipeline.jobs.opinion_source_crawl --apply

# 忽略 24 小时缓存，仍使用相同的少量观点及请求上限
pipeline/.venv/bin/python -m pipeline.jobs.opinion_source_crawl --refresh --request-limit 30
```

默认 dry-run。`--apply` 仅替换本轮规则拥有的目录项，保留其他目录项；每次重新验证失败的关联不再导出。原帖、译文、分数和排名不修改，重复运行不重复添加。抓取结果保存正文哈希、抓取时间与对应表述哈希，便于追溯；来源发布/修订时间分别保存。日期只有年月日的材料不制造具体发布时间，同日先后不明则拒绝关联。

当前只更新 `contracts/fixtures`，本地 fixture 模式需重新构建 App 才会读取新资源；不会自动替换线上 API 的数据，也没有部署服务器或启动定时抓取。

## 官方材料候选渠道（2026-09-22）

原先只有两条人工目录记录和四条定向抓取观点，不足以持续发现新材料。新增 `pipeline.jobs.official_source_refresh`，按审核过的发行人身份收集 **AAPL、COIN、CRCL、CRDO、CRWD、GOLD、INTC、MSTR、MU、NBIS、NVDA** 的 SEC EDGAR submissions 元数据；其中 NVDA、MU、NBIS 还配置公司官网新闻/RSS。Strategy 新闻站点的 robots 请求返回 403，故暂只使用其 SEC 渠道，不绕过限制。首发目录中的 SOXL 是 ETF，尚未配置基金披露身份，不混成单一公司的公告。来源配置在 `pipeline/domain/opinions/official_channels.py`；SEC JSON/RSS/官网目录解析在 `pipeline/platforms/source_documents/official.py`，复用原抓取器的 robots、HTTPS、公开 IP 固定连接、限速和 2 MB 上限。CIK 来自本地发行人元数据，抓取时还要由 SEC 返回的 CIK 和 ticker 双重核对；官网域名和文章路径须在白名单内，不从搜索引擎结果推断官方身份。

- SEC 使用官方 `data.sec.gov/submissions/CIK##########.json`，只记录 8-K、10-Q、10-K、6-K、20-F 及其修订版的表单、日期、主文件地址；**SEC 接收申报不等于认可发行人观点**。SEC 要求声明身份的 User-Agent，运行前设置 `BSMART_OFFICIAL_CONTACT` 为运营方真实联系邮箱；未设置时跳过 SEC 并将该渠道标为 `not_configured`，不编造身份。
- 官网渠道读取 NVIDIA 官方新闻 RSS、Micron 官网新闻和 Nebius 新闻室。页面失败、robots 禁止、非官方跳转、RSS/JSON 结构变化时不绕过或写入伪记录；上一份成功索引保留，`health.json` 标记失败及 48 小时新鲜度。各站渠道独立，另一渠道的成功不会掩盖故障。
- 候选索引写入 git 忽略的 `data/runtime/official-sources/index.json`，只保存标题、日期、URL、正文哈希和来源身份，不保存/再分发全文。`health.json` 提供逐渠道状态、最后成功时间、覆盖标的和缺口。连续刷新按 URL 去重，保留一年候选；抓不到可信发布日期时留空，不猜测时间。
- **候选不是观点依据**。审核人员仍需核对作者原帖、确切事实、来源短摘录、发布日期/修订时间和前后关系，再录入审核规则或目录。`opinion_source_crawl` 仅在规则显式设置 `useOfficialIndex: true` 时，以同发行主体、同日、同标题关键词从候选索引补充 URL；原有逐句核验和 `--apply` 发布门禁不变。只因同标的或同日期不允许自动关联。

```sh
# 每日/每 6 小时可调度一次；设置真实运营联系邮箱后启用 SEC 通道
export BSMART_OFFICIAL_CONTACT='your-team@example.com'
pipeline/.venv/bin/python -m pipeline.jobs.official_source_refresh

# 阅读候选及健康状态；退出码 2 表示至少一个渠道不健康/未配置
pipeline/.venv/bin/python -m json.tool data/runtime/official-sources/health.json

# 对已审核的少量观点规则核验，默认不写正式目录
pipeline/.venv/bin/python -m pipeline.jobs.opinion_source_crawl --official-index data/runtime/official-sources/index.json
```

这是一条**后台材料发现渠道**，不是用户侧新增的官方账号追踪或通知。当前只落地本地可重复运行的刷新任务和审核入口，**没有部署定时任务，也没有把新候选自动推送到线上 App**；运行方需配置运营邮箱、调度和健康告警，并继续现有审核/导出/发布流程。SEC API 文档与 User-Agent 要求参见 [SEC EDGAR API](https://www.sec.gov/search-filings/edgar-application-programming-interfaces) 和 [SEC Webmaster FAQ](https://www.sec.gov/about/webmaster-frequently-asked-questions)；NVIDIA 的 [官方 RSS 入口](https://investor.nvidia.com/investor-resources/rss/default.aspx) 可校验新闻 feed 来源。

本机验证（2026-09-22）：使用运营联系邮箱运行刷新任务，11 只普通股全部有健康 SEC 渠道，另 3 个官网渠道健康；一年内候选共 257 条，`degraded=false`，SOXL 仍未接入。邮箱只在进程环境中使用，未写入仓库或索引。现有少量观点规则的 dry-run 复核了 3 条 Nebius 官网关联；两条 AP 新闻样本因源站访问失败未在本轮重新通过，未执行 `--apply` 或覆盖原发布资料。这说明候选发现已可运行，但历史新闻关联仍须逐条复核，不能把候选总数当成 App 中已展示的依据数量。

## 更新与验证

只对已有 JSON 导出补充或移除资料，不访问线上数据库：

```sh
pipeline/.venv/bin/python -m pipeline.jobs.opinion_sources \
  --input-dir contracts/fixtures --output-dir contracts/fixtures
```

也可指向正式数据的 staging 目录，再沿用该环境现有发布流程。`--catalogue` 可显式指定审核目录。批量 Smart Account 导出与 X realtime worker 已内置同样投影步骤，不必在 API 服务增加来源检索。

修改或撤回关联后必须重新导出并发布所有受影响集合。已下载的离线快照在正常刷新后更新；没有另外建立实时撤回推送。本次只更新本地代码与构建样本，没有部署 Vultr 或上传 TestFlight。

验证覆盖六类来源、旧 API 兼容、逐帖隔离、主观观点、日期先后、无效链接、重复资料、撤回、发布/ETag、真实观点导航与返回、无依据的隐藏状态。保留原稿未关联时的评分与正文。

原研究中的市场机制和链接仍可参见 [历史调研](official-context-proposal.md)，但其中官方渠道追踪不再是本项目需求。

## 本轮验证记录

- 本地爬虫实跑：4 条当前观点、5 条资料关联；原两条历史样本保留，技术分析对照仍不展示模块。再次 `--apply` 后两个观点集合的文件哈希完全一致，没有重复附件。
- 本地抓取新增回归：79 项定向 Python 测试通过；iOS 构建及 7 项模型、2 项 UI 测试通过，包含新增样本解码、修订时间先后、来源详情返回和无来源隐藏。架构边界检查、编译检查及 `git diff --check` 通过。
- `make ios-build` 成功；5 个模型测试和 2 个原生 UI 测试通过，包括真实 NBIS 代表作的资料卡片、详情、返回与无资料隐藏。
- 来源处理、导出、实时投影、API 发布/ETag、架构边界及 Smart Account read model 的 50 项定向 Python 测试通过；`git diff --check` 通过。
- 扩展回归未全绿：既有 X 合规测试使用 2026-08-05 样本，现已超出默认 30 天窗口；旧 API 综合测试仍硬编码 feed 为 5 条，与当前共享样本不符；`make contract-check` 被现有 Smart Money 代表作 `cab821de-fb9b-560e-9a72-09ea258f3a07` 的行情蜡烛数据阻断。这些失败不涉及本次字段或匹配逻辑，未为通过测试改写它们。
- 未部署服务器、上传 TestFlight、重算排名或运行全库采集。
