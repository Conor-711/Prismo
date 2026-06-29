# 项目架构与结构（ARCHITECTURE）

> **维护约定**：本文件是项目的「活地图」。**每次对项目结构或功能有实质改动后，必须同步更新本文件对应章节**
> （新增/删除模块、改数据流、改命令、改部署方式、改 schema 等）。详见根目录 `CLAUDE.md`。
> 最近更新：2026-06-29。

---

## 1. 这是什么

**Prismo** —— 一个多语（中文默认 / English / 日本語 / 한국어）的 **多社区美股舆情聚合看板**：聚合 **Reddit / Yahoo Finance Japan / Naver / 雪球 / PTT** 五大本土散户社区，对同一批跨区美股做情绪对比、共识与分歧分析，最终渲染成一个**纯静态网站**。
（注：早期作为 Reddit 单站「redditalpha」起步——抓 Reddit 财经社区帖、逐帖大模型打标、聚合声量/情绪/异动/叙事/简报；该 Reddit 管线仍是后端基础，新增 4 区由 `gr_*` 表承载。）

- 线上地址：**https://www.redditalpha.xyz**（根域名，静态托管）
- 两个市场（market）：`us`（美股）、`cn`（中概股 + 港股 + A 股），互不污染，各出一套聚合。

> **⚠ 价值判断 / 护城河（别被「海外散户视角」叙事带偏）**：
> 1. **最有价值的内容并非「非英语散户对美股的个体看法」本身。** 韩国 Naver、日本 Yahoo 掲示板等本土股吧**单帖信息质量普遍很差**——多数是水帖、情绪宣泄、无意义 shitpost；这类内容**只有靠「量」做聚合分析才有价值**（情绪分布 / 声量异动 / 跨区分歧），逐条看几乎没有信息量。
> 2. **抓取这些股吧本身不构成技术护城河。** 爬取门槛很低（人人有个 crawling agent 都能爬），技术不是壁垒。

> **🎨 UI 已按 QuiverQuant 风重建（2026-06）**：品牌 = **Prismo**（仓库 `Conor-711/Prismo`）。**设计系统（复刻 QuiverQuant）**：字体 Figtree(UI/标题)+Roboto(数据/数字 tabular)；默认深色底 `#121212`（卡片 `#161616`，靠 `#2a2d2f` 发丝边区分；图表底才用 `#202630`；**仅深色**、已彻底移除白天模式 CSS 回退与主题切换）+ 青绿强调 `#57D7BA`（Tailwind `reddit`/`amber`/`brand`/`bull` token 同值；看跌珊瑚 `#FF5C6C` 全站统一、不随地区红绿翻转；品牌渐变青绿→深松绿、去紫）+ 小圆角(2–4px) + 数据密集卡片/表格 + 等宽数字；侧边栏导航（`globals.css` CSS 变量 + `tailwind.config.ts`）。**完整设计语言宪法见 `DESIGN_LANGUAGE.md`（改 token 前后都要同步）**。
> **12 个页面**（数据多走 `gr_*` → `lib/globalQueries.ts`，投资者/作者页另走 `investorQueries`/`creatorQueries`）：**落地页**(`/`：中文 slogan「时间即金钱 / 两者皆盈利」hero + 「噪音→信号」三步 + 五社区五地区 + 注册/进看板 CTA，文案在 `dict.home`；**无侧栏 chrome**——`app/[lang]/(marketing)/page.tsx` + `(marketing)/layout.tsx`(品牌头 logo/语言/登录-注册 + 页脚)) · **总览看板**(`/dashboard`：实时 KPI/分歧·多空/五地区情绪/全球热度榜/跨区热力图；原 `/` 内容已迁此，侧栏「总览」指向它) · 标的总览(`/tickers`，表格上方有 **KOL 看多/看空/情绪变化最大 三个标的排行榜**) · 标的详情(`/tickers/[symbol]`) · **投资者榜单**(`/investors`) · 追踪/自选(`/tracking`) · 区域总览(`/regions`) · 区域详情(`/regions/[region]`) · 搜索(`/search`) · Profile(`/me`) · 设置(`/account`)。**投资者榜单页**(`/investors`)：服务端 `lib/investorQueries.ts` 的 `getInvestorBoard()` 从真实数据按平台聚合活跃投资者(X=`x_opinion` 按 handle 去重推聚互动 + unavatar 头像；YouTube=`yt_video` 按 channel_id 聚播放量 + `author_avatar` 头像；Reddit=`posts`⋈`mentions` 按 author 去重帖聚互动；雪球=`gr_post` source=xueqiu 按 author 聚互动)，烤进页面壳；客户端 `components/prismo/InvestorBoard.tsx` 顶部平台过滤(全部=每平台前 6 预览/可点进看全部 24，选中=单平台完整榜)，卡片含名次/头像/外链/覆盖标的 chips/主指标(互动或播放)。入口在主侧栏(`NAV_GROUPS`，`IconTrophy`)+移动端底栏，四语标签 `dict.nav.investors`。**YouTube 作者页**(`/investors/youtube/[channelId]`，投资者榜单的下钻)：服务端 `lib/creatorQueries.ts` 的 `getYoutubeCreator()` 按单频道聚 `yt_channel`(档案)+`yt_video`/`yt_analysis`(立场/笃定/**观点 summary/论据 key_points/目标价 price_target**)+`price_daily`(自表态日起收益；有 SPY 则算超额)+`author_avatar`(头像) → **① 标的判断**(2026-06-29 由原「含权标的表现」表升级为 `tickerJudgments`：**按标的归组的综合判断**(2026-06-29 二次精简：不再逐条铺开每条视频[太繁杂]，**每标的综合成几点关键判断**)——立场含**中性**；每标的展示 综合立场+多/空/中性计数 · **几点关键判断**(`yt_creator_view` 综合该作者对该标的多条视频、合并去重；见下表) · **代表性回测**(取最早一条方向性表态：当时价→现在价+涨跌%+命中✓✗) · 代表性 目标价/时间周期/关键位置 chip · 基于 N 个视频(dated 原视频链接)；顶部汇总沿用方向性回测 命中率/按方向平均/可回测数，**短窗小样本诚实标注**、无 SPY 隐藏「跑赢大盘」、表态过近或缺价标「暂无回测价」；**时间周期/目标价/关键位置** chip 由 `yt_judgment`(见下表)结构化抽取填充——`youtube_judgment.py`/`make youtube-judgment` 跑 **LOW 档 qwen-flash** 从 `yt_analysis` 观点/论据**纯文本抽取**(不重看视频)、**只抽明说不臆造**(776 条仅 ~105 有值、属正常)、双语 + 目标价结构化优先于原始 `price_target`；creatorQueries `safe` 单独查 `yt_judgment` + `yt_creator_view` 各自兜底、表缺失不影响主流程) + **② 互动最高视频**(**2026-06-29 删除原「代表性标的」模块**、原③互动最高视频改②)；客户端 `components/prismo/CreatorProfile.tsx` 渲染(两块；立场配色/日期本地常量，不 dot 进 "use client" 的 kolShared)；`generateStaticParams` 枚举 `yt_video` 全部 channel_id；**投资者榜单的 YouTube 卡片改内链到此页**(其余平台暂外链)。文案 inline `zh?:en`(ja/ko 回退 en)，未走字典。**追踪页**(`/tracking`)：服务端把全部标的摘要(`getGrTickers`+`getGrTickerRegions`)烤进页面壳，客户端 `TrackingView` 按登录用户的 `user_collections`(kind=`ticker`) 过滤出追踪集，按情绪/热度/时间排序，逐个展示「情况」(平均情绪·共识·覆盖区/帖数/分歧·跨区多空条·各区情绪)；未登录显示登录引导、空集显示去发现标的(与 `ProfileView` 同范式)。入口在**主侧栏导航**(`components/nav.tsx` 的 `NAV_GROUPS`，星标图标 `IconStar`)与移动端底栏，四语标签 `dict.nav.tracking`。展示件在 `components/prismo/`（Bits/TickerTable/TickerSearch/TickerLogo/TrackingView + 详情页模块件 DetailCharts/DetailBits/HotList）+ 复用 `components/asia/AsiaCharts`（ECharts）；地区元数据在 `lib/regions.ts`。**详情页（标的/地区）已做成图表化「模块看板」**，当前用 `lib/mockDetail.ts` 的演示数据（确定性 mock，接真实管线前占位）。**标的详情页顶部 = 四方图(身份KOL/散户 × 视角主观/客观)象限①「个体观点·KOL」**：`components/prismo/KolOpinionFlow.tsx`（client，ECharts）—— **数据已接真实**(`lib/kolQueries.ts`：价格取 `price_daily`(Yahoo 日 OHLC) + 观点取 Reddit(posts/mentions/item_analysis) + YouTube(yt_video/yt_analysis) + 雪球(gr_post source=xueqiu)；**X 真实**(云端 `tw_tweet`⋈`tw_tweet_ticker` 拉进本地 `x_opinion`，原生无情绪→取 `kol_refined` 提炼立场)；数据不足回退 `getKolFlow` mock)。**观点已 AI 提炼+双语（不再照搬原文）**：`pipeline/analyze/kol_refine.py`(`make kol-refine`) 对 reddit/x/雪球 每标的每源 **top-N(默认 20)** 各跑一次 DeepSeek(flash) → 隔离表 `kol_refined`(PK source+item_id：stance/reason_zh·en/points_zh·en/**quote_zh·en(本人忠实原话，建立可信度)**，提炼「为什么看多/看空/中性(1-2句) + 2-4 要点(**保留数字/事件细节、放宽压缩**避免长帖被压成一句) + 原话」，**提炼与翻译合一**)；YouTube 复用 `yt_analysis`(summary→reason、key_points→points，不重花 Gemini 配额)；**原帖卡(`OpinionCard`)统一展示原帖原文 + 「译」选项**(与原帖流共用 `kolShared.pickOriginal`；reason/要点不再当卡片正文、仅图表 tooltip `opinionText` 用)；**翻译只 zh/en，ja/ko 前端回退 en**（产品决策）；增量(只补未提炼，`--force` 重跑)。价格走势已移到**页头卡**作迷你折线（`PriceSparkline`：近 2 周收盘价，无坐标轴/滑块，涨青绿/跌珊瑚红 + 末点标记）。KOL 模块内只剩 **每日净情绪折线**(`SentimentPanel`：绿(>0 看多)在上 / 红(<0 看空)在下、各自从 y=0 起填充的 Kaito 风面积折线；net = 跨平台 情绪×ln(1+互动)×相关性 加权净值，来自 `kol_sentiment_daily`；展示完整近 2 周、无区间滑块) + **每日讨论度条状图**(`VolumePanel`：各平台讨论该标的的帖子/视频**计数**堆叠柱，x=逐日历日[含周末、一日一柱不折叠]、y=当天总量，与情绪面板同日期范围；来自 `kol_volume_daily` 经 `getKolVolumeDaily`) + 下方 `OpinionExplorer`(精简工具条筛选 + 主从精读)。**KOL 模块顶部有「KOL ↔ 整体散户」人群切换**(`KolModule` 的 `cohort` state)：只切换上面两张图的数据源——KOL=现有 `kol_*_daily`(X/YouTube/Reddit/雪球)，整体散户=`retail_*_daily`(全量散户+本土论坛 Naver/YahooJP/PTT/Toss、**去 YouTube**)；`VolumePanel` 已泛化为按 `stack`(VolStackItem[]) 配置平台层(`kolShared.KOL_VOL_STACK`/`RETAIL_VOL_STACK`)，`SentimentPanel` 仅读 net 故两口径通用；**观点浏览器始终是 KOL 个体观点**(切换只影响两图)。散户数据走 `getRetailSentimentDaily`/`getRetailVolumeDaily`，缺数据时不显示切换入口(`hasRetail`)。**模块标题已更名「情绪与讨论度」→「整体数据」**（后续不止情绪/讨论度、还反映标的整体形势）。**整体散户视图下多第三张图『每日新增散户』堆叠条状**(`VolumePanel` + `RETAIL_NEW_STACK`)：各平台**首次参与该标的讨论**的去重作者数（"数据集内首次"——用户对该标的最早出现日计 1），来自 `retail_newcomers_daily`(经 `getRetailNewcomersDaily`)；平台=Reddit(发帖+评论)/雪球/Naver/YahooJP/PTT/Toss、**不含 X**(云端 `tw_tweet_ticker` 无作者列)/YouTube；仅整体散户视图、有数据才显示(`hasNewcomers`)。**KOL 视图的『每日新增 KOL』图已于 2026-06-28 从 UI 删除**(`KolModule`/`page.tsx` 去掉 `kolNewcomers` 入参 + `KOL_NEW_STACK` 引用；数据层 `kol_newcomers_daily`/`pipeline kol_newcomers.py`/`make kol-newcomers` 仍在、只是不再渲染；『新增散户』仍在整体散户视图保留)。`VolumePanel` 现支持可选 `title/subtitle/unit`(默认仍「每日讨论度」)。**『整体数据』另有两块仅 KOL 的 AI 派生信号**：① **异动归因**——情绪/讨论度异常日在折线/条状上打**金色 ⚑ 标记**、hover 当天出 AI 一句话归因(情绪跑**交易日序列**、讨论度跑**日历日序列**，各按**滚动 14 日基线 |z|≥2** 取前 3；当天 top KOL 推文喂 qwen-flash；经 `SentimentPanel`/`VolumePanel` 的可选 `markers` 入图，**仅 KOL 口径**、切散户隐藏)；② **聪明钱 ↔ 散户 分歧**(`DivergencePanel.tsx`，**Prismo 独有护城河**，常显在模块**顶部**、独立于人群切换)——两条净情绪线：**聪明钱**=技能加权 KOL(只取跨标的验证过**正技能 z** 的作者、按 z×ln(1+互动) 加权；z 由 `overall_signals._skill_map` 复刻 `gen_topinvestors` base-rate 校正 z) vs **散户**=`retail_sentiment_daily`；各按自身峰值归一到 [-1,1](比方向/分歧)，顶部读数(谁多谁空 + 一致/背离)、背离日打金钻。两者离线由 `pipeline/analyze/overall_signals.py`(`make overall-signals`，qwen-flash + `/tmp/mt_*` 技能缓存 + `<ticker>_x6m.jsonl`)→ **构建期 JSON `web/lib/data/overallData.json`**(与 `topInvestors.json` 同范式：web 经 `lib/overallData.ts` 的 `getOverallData` 读、不碰 dev.db)，**当前 PLTR + NFLX**(各按 `--window` 交易日窗口；NFLX 用 14 日)。每个新标的需 `/tmp/<t>_x6m.jsonl`(roster 抽取)+ `_stance.json`(qwen-flash 打标)。**实测：PLTR 聪明钱领先转空、一致看空；NFLX 6/16 聪明钱+0.65 vs 散户−1.0 真背离(Roku 传闻日)。** ⚠ **2026-06-28 删除**两个原型「近期最密集讨论方面」(DiscussionAspects)+「新叙事」(NewNarratives)：前端组件删除、`overall_signals` 不再产出 `aspects`/`narratives`。⚠ "数据集内首次"在各平台数据窗起点会偏高(尤其 Toss 仅 06-14 起、近窗多为 Toss 新增)，已在小标题标注。**页头卡**把基本信息(logo/名称/代码·交易所/价格 + 迷你价格折线)与关键指标(平均情绪/风险温度/多空比/共识/最强异动/讨论帖)**合并为一张卡**(原独立 KPI 行上移)。**KOL 模块结构**(`KolModule.tsx`)：**常驻**「股价×观点折线 K 线图」(`KolOpinionFlow`，底部 dataZoom 滑块**只控图本身**) → **紧贴图下方『每日净情绪』联动子面板**(`SentimentPanel.tsx`，Kaito 风绿(>0 偏多)/红(<0 偏空)面积，与图共享 days+range；数据=`kol_sentiment_daily` 经 `getKolSentimentDaily`) → 下方**观点浏览器**(`OpinionExplorer.tsx`，2026-06 重构、**替代原 按KOL/按视角/按热度 三 tab**)：顶部**精简工具条**(2026-06-28 去拥挤：**平台=仅 PNG 品牌 logo 切换**(`web/public/platform/{x,youtube,reddit,xueqiu}.png`，圆角小图标，空选=全亮/选中=亮+青环) / **时间=单下拉**(菜单含 24h·3d·7d·14d·1mo 模板 + 自定义起始 date picker) / **语言=单下拉**(简中·英·日·韩·繁中 多选；繁简按高频分歧字启发式分) / **质量**开关 / **排序**[相关度·最新]收到工具条右侧；下拉是 `Dropdown`/`MenuItem` 轻量浮层，已**取消 立场/视角 维度筛选**) + 下方**主从阅读**(左**窄列 ~300px**=帖文卡列表[**左 3px 色边=立场** + 头像 + handle + 平台 logo + 日期(灰)；**质/相关/互动数字已移出卡面**——它们是排序键、详情在右栏读]，右**宽栏 flex-1**=选中帖的**完整原文**；**左右各 `max-h-[640px] overflow-y-auto` 独立滚动**——长文只在右栏内滚、不撑整页(YouTube 阅读器传 `noCollapse` 不再二次折叠) + 视角标签 + 「译」+「查看原帖↗」+ **X 专属**：「**互动数行**」(赞/转/评/看/藏 五图标，与 X 原生底栏同序，来自 `x_opinion` 逐项列；X 头部不再重复合计数) + 「**热门评论**」(帖下点赞 top-3，含小头像/@handle/❤数/评论原文/回链，来自 `x_reply`) + **YouTube 专属**：作者头像旁「**基础信息**」(粉丝数 · 视频数 · @handle · 个人简介，来自 `yt_channel`))，列表头可切**排序**「相关度 / 热度 / 最新」(热度=互动量降序)、**默认相关度降序**。⚠ 相关度**只做排序、不做筛选**(用户只想看高相关的，设低相关过滤无意义)。数据=`getKolOpinions(symbol)`(`kolQueries.ts`：近 ~32 天**扁平池**、不 snap 交易日，每条带 orig/trans/quote/viewpoints/**relevance**)；6 个维度筛选全在前端做。理念延续「**展示原文、不蒸馏**；AI 只做分类/翻译/相关性打分等『索引』活」。**AI 顺序：kol-refine(立场/原话) → kol-viewpoint(视角) → kol-translate(译) → kol-relevance(相关性)**(都走 LOW=千问 qwen-flash，需 `QWEN_API_KEY`)。⚠ 原帖完整度：X/雪球/Reddit=全文(Reddit 译文用 `posts.selftext`；卡片正文目前仍只显示标题、回链看全文)、YouTube=AI 摘要(无字幕)。**「译」**见 `kol_translate.py`(逐句直译、不压缩 → `kol_refined.trans_zh·en`；**目前只译已提炼 top-N**，故长尾展示帖暂无「译」)，**「相关性」**见 `kol_relevance.py`(0-100、覆盖 4 源、打全部展示帖 → `kol_relevance`，**只用于排序**)；**「质量」**见 `kol_quality.py`(0-100 内容含金量、**与标的无关**故按 source+item 去重 → 隔离表 `kol_quality`，供「只看高质量」开关)。**数据清洗**：雪球 `body` 富文本在 `kolQueries.stripHtml` 去 HTML 标签；X **纯转推**(`text` 以 `RT @` 开头)在 `xOps` 从展示中剔除(RT'd 原文被截断、源推不在库，无法还原)。**旧件 `ClassifiedOpinions.tsx` + `kol_argument`/`kol_narrative`(论点综合/叙事编织)已不再被 UI 使用**(保留在库/管线、待清理)。取文/卡片/配色在 `kolShared.tsx`(`pickOriginal`/`OpinionCard`/`Avatar`)。(象限① 管线：提炼→视角分类→翻译→相关性打分，前端=观点浏览器；2/3/4 待后续。)价格抓取器 `pipeline/ingest/price_daily.py`(Yahoo chart API、免 key、plain ticker；当前直接写**本地 `dev.db`** 的 `price_daily` 表；标的全集 = `gr_ticker` ∪ **`yt_video` 标的(供作者页表现)** ∪ **`SPY` 基准(算超额/跑赢大盘)**，`ticker_meta` 兜底；⚠ 生产化需改成 session_scope 写云端 Supabase + cloud-pull，否则下次 cloud-pull 会覆盖。⚠ Yahoo/stooq 在沙箱/数据中心 IP 常 403/JS 墙——需从普通住宅网跑刷新)。X 拉取 `pipeline/ingest/x_pull.py`(云端 `tw_*`→本地 `x_opinion`+`x_reply`：x_opinion 带**逐项互动数**[赞/转/评/引/看/藏，列 likes/retweets/replies/quotes/views/**bookmarks**]；x_reply=**每条推文下按点赞 top-K**[默认 3]的**热门评论**，由 `tw_tweet.in_reply_to_tweet_id` 自关联 + 窗口函数取，覆盖 ~25% 展示推文；两表均全量重建)。**观点卡作者头像** `author_avatar` 表(`pipeline/ingest/author_avatars.py`)：YouTube 抓频道页 `yt3` 头像(540 ✓)、Reddit 走 app-only OAuth `icon_img`(**需 `.env` 填 `REDDIT_CLIENT_ID/SECRET`，当前为空→跳过、兜底首字母**)；X 走 `unavatar.io/twitter/{handle}`(客户端、onError 兜底)；雪球(阿里云 WAF)暂兜底。**⚠ 这些脚本须用 venv `pipeline/.venv/bin/python`**——系统 `python3` 无 python-dotenv → 读不到 `.env` 的云端 `DATABASE_URL`/凭证(会误判成 sqlite/无凭证)。标的详情头部：`TickerLogo`(第三方 CDN logo + 字母兑底) + 全称/代码·交易所(`lib/tickerMeta.ts` 预设) + 最新价/涨跌幅(来自数据层 `gr_quote`，纯静态站随构建刷新、非逐笔实时)。各列表行也带 logo。
> **标的页『目标价 × 操作周期』(2026-06-29 新增)**：① **观点检索/正文提炼**——每条观点抽到时在 reader 多显一行「作者明确给出 买入/卖出/目标价 + 周期(原话+档)」(`OpinionExplorer` 的 `JudgmentLine`)；② **整体数据**——`KolModule` 底部新增 `TargetPricePanel` 散点(x=周期档 短/中/长/未注明、y=目标价、点=KOL ▲买/▽卖/●目标、绿多红空、现价虚线基准；jitter 分散、同条 buy/sell 共享 x；只给周期无价者列图下方)。抽取层=独立表 `kol_judgment`(reddit/x/雪球，见 §5)+ YouTube 复用 `yt_judgment`；**只抽作者明说、反臆造**，价格在 `kolQueries.judgmentMap` 按**现价 0.2–5× band 剔噪**(penny-pump/假设估值/$1225 这类数量级离谱者置空)。取数 `getKolTargetPrices`(复用 `getKolOpinions` 池，judgment 挂到 `KolOpinion.judgment`)。`make kol-judgment`。
> Reddit 单站旧页（dashboard/ticker/post/author/leaderboard/cn/onboarding）已删；**后端 pipeline 全保留**。线上 redditalpha.xyz 仍由旧 `reddit_alpha` 仓库部署、不受影响（Prismo 部署需快照含 `gr_*`，否则相关页为空）。

---

## 2. 三大系统

> **⚠ 两站两套数据、互不干扰（2026-06）**：本仓库 = **prismo.today**（完整多社区），数据真源 = **本地 `data/dev.db`**（含 gr_*/yt_*/kol_* 等云端没有的独有层）；旧站 **redditalpha.xyz** = `Conor-711/reddit_alpha` 仓库（只 Reddit），数据 = 下面的 Supabase 云端。**Prismo 不再 `cloud-pull`**（它会用「只有 Reddit 核心」的云端快照覆盖本地、抹掉独有层 = 之前『数据消失』元凶；已在 Makefile 锁死：`site-cloud`=`make site`、`cloud-pull` 默认拒绝、`clean` 不删 db）。出站 `make site` 读本地 dev.db。

```
┌─────────────────┐  写本地   ┌──────────────────────┐   读本地   ┌─────────────────────┐
│ ① Python 数据管线 │ ───────▶ │ ② 本地 data/dev.db       │ ───────▶ │ ③ Next.js 静态网站   │
│  抓取 + AI 分析   │  (默认)   │  Prismo 唯一真源(gr/yt/kol)│  构建期    │  读 dev.db → 出 HTML │
└─────────────────┘          └──────────────────────┘          └─────────────────────┘
        │  只读拉 tw_*(X)            ▲ Supabase 云端 = redditalpha 的 Reddit 核心
        └──────────────────────────┘   + Prismo 的 web 后端(Auth/app_events/收藏)，ref wimipsiwtrqhizgmbxas
```

### ① Python 数据管线（`pipeline/`）
抓 Reddit → 抽取 ticker → 大模型逐帖打标 → 聚合（榜单/情绪/异动/叙事/简报）→ 翻译；+ 5 社区 `gr_*`、YouTube `yt_*`、KOL `kol_*` 等扩展层。
**Prismo 内容写本地 `data/dev.db`**（`DATABASE_URL='sqlite:///./data/dev.db'`）。**X 数据 `tw_*` 从云端只读拉**（`kol_sentiment.py`/`kol_volume.py` 的 `_cloud_url()` 直接读 `.env` 拿云端串）。

### ② 数据真源 = 本地 `data/dev.db`（Prismo）
- Reddit 核心（14 表）+ **Prismo 独有层** `gr_*`(5 社区)/`yt_*`(YouTube)/`kol_*`/`x_opinion`/`price_daily`/`author_avatar` 等（这些云端**没有**）。
- Railway/Dockerfile 用**提交进镜像的 `data/dev.db`** 构建（线上=本地；`.dockerignore` 对 `data/dev.db` 开例外）。改数据前先 `make backup-db`。
- **Supabase 云端**（`wimipsiwtrqhizgmbxas`，**不是 Prismo 的内容家**）：① redditalpha.xyz 的 Reddit 核心；② Prismo 的 **web 后端**（`app_events`/`ticker_searches`/`user_collections`/`user_profiles`/Auth，走 `NEXT_PUBLIC_*`）；③ Prismo 只读的 `tw_*`(X)。见 `CLOUD_DB.md`。

### ③ Next.js 静态网站（`web/`）
Next 14 App Router，**静态导出**（`output:"export"` 仅生产）。构建期用 `node:sqlite` 读**本地 `data/dev.db`**
（Prismo 真源，**不再 cloud-pull**），生成 ~6500 个静态页面到 `web/out/`，可部署到任意静态托管。
**网站运行时不连数据库**（纯静态，无服务端攻击面）。

---

## 3. 端到端数据流

```
Arctic Shift / PRAW ──▶ posts/comments ──▶ ticker 抽取(正则) ──▶ mentions
                                                                   │
                                          大模型逐帖打标(qwen 思考模式) ──▶ item_analysis
                                                                   │
        ┌──────────────┬──────────────┬──────────────┬────────────┘
     rollups        market_mood     trending      narratives(deepseek) + brief(deepseek)
   (声量/情绪榜)     (市场情绪)      (异动z-score)   (主导叙事 / 每日简报)
        └──────────────┴──────────────┴──────────────┴──────────── translate(deepseek, 增量补中文)
                                       │
                              全部写入 Supabase 云端
                                       │  make cloud-pull
                              本地 data/dev.db 快照
                                       │  make site  (Node 22)
                                  web/out/ 静态站
```

**关键：分析是增量的** —— 逐帖打标按 `item_analysis.item_id` 持久化，只分析新帖；聚合表每次全量重算（纯 SQL，0 token）。

**作者库（优质作者聚合页）** —— `make daily` 内（主分析之后）爬「实力榜」Top 50 作者的 Reddit 历史帖，
两级模型漏斗控成本：**DeepSeek(LOW) 粗筛质量 → 仅过线帖送千问(HIGH) 深析并入库**。这些帖标记
`posts.source='author'`，**被所有实时舆情聚合/feed 排除**（`source='scan'` 过滤），只出现在作者页与其自身帖详情页。
入口：全站作者名/头像 → `/[lang]/author/[name]/`。详见 `pipeline/ingest/author_crawl.py`。

**亚洲散户舆情看板（隐藏页）** —— 把舆情看板扩到日韩台本土散户社区的实验。**近 7 天**爬三市场：
**日本 Yahoo Finance 掲示板**（`/quote/{CODE}/forum`，SSR；按 NVDA/MU/NOK/SPCX 四标的，SpaceX=SPCX pre-IPO 专板）、
**韩国 Naver**（`m.stock.naver.com/front-api/discussion/list`，foreignStock+itemCode；同四标的；`comment/counts` 补评论数）、
**台湾 PTT Stock**（`ptt.cc/bbs/Stock/`，SSR，`M.{epoch}` 解析发文时间翻「上頁」拿一周；**综合板→board 级聚合 market=`tw`/ticker=`TWSTOCK`**，标题 [類別] 当 label）。
每帖富化维度：likes/dislikes/views/comments/images/verified(持股认证)。
**两级 AI 打标**：① HIGH 千问逐帖双语深析(Top~12/格，供详情) → MID DeepSeek 每格汇总；② **LOW DeepSeek flash 给
全部帖打情绪分**(`asia_posts.sentiment`，便宜+批量，供每日时间序列/变化)。**价格**：Naver 日K(`asia_price` 表，
NVDA/MU/NOK 全序列；SPCX pre-IPO 稀疏)。全部写**隔离表** `asia_*`（market `jp`/`kr`，不污染 us/cn）。
命令 `make asia`（crawl --since-days 7 → score → analyze → summarize → price）；页面 **`/[lang]/lab/asia-pulse`** 是
**多维看板**（情绪矩阵 / 台湾区 / 跨市场分歧 / 声量榜 / 每日声量 / 主题 / **趋势+异动榜** / **价格×情绪×声量 ECharts 指数图** / 8 格详情；
无导航入口、不进 sitemap、noindex，仅 URL 直达）。**「机构级指标」区**（对标 Swaggy Stocks/Buzzberg/E*TRADE，让每个抓取维度都发挥作用）：
净情绪榜(多−空发散条) / 舆情定位气泡(净情绪×声量×互动) / 情绪日历热力(标的×日) / 声量异动 z-score(本周最反常日,σ) /
市场画像雷达(日韩台 5 维归一化) / 认证持仓 vs 大众(Naver verified 聪明钱代理) / 认可度&争议(赞踩比) / 日本自评(类 Stocktwits) / 主题情绪倾向。
新增查询 `getAsiaSentiHeat/Engagement/VerifiedSplit/JpSelfRating/ThemeStance`（`asiaQueries.ts`）+ 图表 `AsiaDivergingBars/Heatmap/Bubble/Radar/PairedBars`（`AsiaCharts.tsx`，均 Client Component，父级只传可序列化 props）。
详见 `pipeline/ingest/asia_crawl.py`、`asia_price.py`、`web/components/asia/`。

**全球散户 · 五地区看板（隐藏页 /lab/global-retail）** —— 与上面的 asia 4 标的实验**不同**：这是 ticker 中心、
**精选 ~40 支跨区高共识美股**、对比 **5 个地区**散户情绪的另一套。区 = **美国(Reddit) + 中国大陆(雪球) + 日(Yahoo) + 韩(Naver) + 台(PTT)**。
近 **14 天**。**US 区不重爬**——rollup 直接**只读**现有 Reddit `mentions×item_analysis×posts`(market=us) 算 stance/情绪（不污染主管线）；
日韩台复用 `asia_crawl.py` 的 fetch 函数（JP 板 `/quote/{SYMBOL}/forum` 美股代码直连；KR `naver_code` 由 autoComplete 解析的 reutersCode 如 NVDA.O；
TW PTT 综合板抓一遍，用繁中/英文别名从标题+正文**抽取**精选标的）。**CN(雪球)** 讨论接口在阿里云 WAF 后面、requests 直连过不去 →
用 **Claude-in-Chrome 真实浏览器**（自然过 WAF）在页面内 XHR 拉 `/query/v1/symbol/search/status.json` 导出 JSON，再 `ingest/global_retail_xueqiu.py` 收进 gr_post(region=cn)。
**打标 = DeepSeek flash 全量（不用千问）**：每帖 sentiment + 派生 stance。
跨区滚动 → `gr_ticker_region`(每 region×ticker 帖数/多空/情绪)；跨区派生 → `gr_ticker`(共识 all_bull/all_bear、分歧 divergent=某区与其余相反、情绪极差 spread)。
页面看板：五地区情绪概览+雷达 / 跨区情绪热力(标的×区) / 五地共识(共同看多·看空) / 地区分歧 / 全球定位气泡 / 全球热度榜 / **标的×五地区明细(逐区情绪条+代表帖)**。
管线：`pipeline/data/global_targets.yml`(40 标的+别名+naver码) → `ingest/global_retail_crawl.py`(+`global_retail_xueqiu.py`) → `analyze/global_retail_tag.py` → `analyze/global_retail_rollup.py`；
CLI `gr-crawl/gr-tag/gr-rollup/gr-xueqiu/gr-quote`（`gr-quote`=抓各标的最新价(Nasdaq api 主 + Yahoo 兜底) → `gr_quote` 表，`ingest/gr_quote.py`），`make gr`（含 gr-quote）/`make gr-quote`；web `lib/globalQueries.ts`。隔离表 `gr_*`（含 `gr_quote`；迁移 `supabase/migrations/…_gr_quote.sql`）。

---

## 4. 目录结构（带注释）

```
crypto_us/
├── pipeline/                  # ① Python 数据管线
│   ├── manage.py              #   统一 CLI 入口（被 Makefile 调用的所有子命令）
│   ├── daily.py               #   每日一次的全量编排（抓取→分析→聚合→翻译）
│   ├── sync.py                #   ★本地 SQLite ⇄ 云端 Supabase 同步（cloud-push / cloud-pull）
│   ├── worker.py              #   调度器（APScheduler，定时跑 daily）
│   ├── common/
│   │   ├── config.py          #   配置/环境变量（含 normalize_db_url：Supabase 串自动转 psycopg+SSL）
│   │   ├── db.py              #   SQLAlchemy 引擎/会话（sqlite 开发 / postgres 生产通用）
│   │   ├── models.py          #   ★数据模型 = schema 单一真源（14 张表）
│   │   ├── llm.py             #   ★大模型「档位路由」：LOW/MID/HIGH → 具体 provider
│   │   ├── qwen.py            #   通义千问（HIGH：逐帖打标，思考模式）
│   │   ├── deepseek.py        #   DeepSeek（MID：叙事/简报；LOW：翻译）
│   │   └── claude.py / reddit.py
│   ├── ingest/                #   抓取 + 抽取
│   │   ├── arctic_scrape.py   #   Arctic Shift 拉历史帖/评论（主力）
│   │   ├── reddit_ingest.py   #   PRAW 实时拉取
│   │   ├── author_crawl.py    #   ★作者库：爬 Top 作者历史帖（DeepSeek 粗筛→千问深析，两级漏斗控成本）
│   │   ├── asia_crawl.py      #   ★亚洲实验：爬日(Yahoo JP)/韩(Naver front-api)/台(PTT Stock)散户讨论 → 隔离表 asia_posts
│   │   ├── asia_price.py      #   亚洲实验：抓 Naver 日K收盘价 → asia_price（价格×情绪叠加图用）
│   │   ├── global_retail_crawl.py # ★全球散户：爬日韩台精选跨区美股(复用 asia fetch；PTT 别名抽取) → gr_post
│   │   ├── global_retail_xueqiu.py # ★全球散户 CN：收 Claude-in-Chrome 过 WAF 导出的雪球帖 JSON → gr_post(region=cn)
│   │   ├── toss.py             # ★Toss(토스증권) 종목 커뮤니티评论：逆向 wts-cert-api /api/v4/comments(无登录、游标翻页) → gr_post(source='toss',region='kr')
│   │   ├── ticker_extract.py  #   ★ticker 抽取器（cashtag/裸大写/公司名别名 + 停用表）
│   │   ├── seed_tickers.py    #   seed ticker 字典 → ticker_meta（含中概/港股 cn_hk_tickers.json）
│   │   └── twitter_match.py   #   ★X 推文↔标的 关键词硬匹配（无AI；读 vertical_topic_metadata.json 的 keywords，混合匹配 $cashtag/@handle/短语/单词 → tw_tweet_topic，仅 Stocks）
│   ├── analyze/              #   分析 + 聚合
│   │   ├── item_analyze.py    #   ★逐帖 AI 打标（analyze_qwen 是全站分析大脑；增量，跳过已分析）
│   │   ├── rollups.py         #   声量/情绪聚合（mindshare 归一化）
│   │   ├── market_mood.py     #   市场情绪（恐惧贪婪）
│   │   ├── trending.py        #   异动（z-score / spike）
│   │   ├── narratives.py      #   叙事聚类（deepseek 语义聚类，失败回退主题分组）
│   │   ├── brief.py           #   每日简报（deepseek 润色）
│   │   ├── asia_analyze.py    #   ★亚洲实验：逐帖打标(HIGH 千问双语)+每格汇总(MID DeepSeek overview)
│   │   ├── global_retail_tag.py    # ★全球散户：DeepSeek flash 全量打标 gr_post(sentiment+派生 stance，不用千问)
│   │   ├── global_retail_rollup.py # ★全球散户：跨区滚动 gr_ticker_region(US 读现有 Reddit) + 派生共识/分歧 gr_ticker
│   │   ├── kol_refine.py       #   ★KOL 个体观点 AI 提炼+双语：reddit/x/雪球 每标的每源 top-N → DeepSeek flash → kol_refined(stance+reason+points, zh/en；提炼与翻译合一)
│   │   ├── kol_viewpoint.py    #   ★KOL 观点 视角分类：对已蒸馏观点(kol_refined+yt_analysis) → DeepSeek flash 打 7 视角(1-3 个,首个为主) → kol_viewpoint
│   │   ├── kol_judgment.py     #   ★KOL 目标价+操作周期 抽取：reddit/x/雪球 原帖**只抽明说**的 买入/卖出/目标价(现价锚点剔噪)+周期 → kol_judgment(独立表，复用 kol_refine._load 候选池)；YouTube 复用 yt_judgment
│   │   ├── tweet_sentiment.py  #   ★X 推文情绪打分：tw_tweet_topic 命中推文 flash 批量 -1..1 → **云端** tw_tweet_sentiment（供每日净情绪）
│   │   ├── kol_sentiment.py    #   ★KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 加权净值 → 本地 kol_sentiment_daily（混合读本地三源+云端 X）
│   │   ├── retail_sentiment.py #   ★整体散户 每日净情绪 rollup：全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube → 本地 retail_sentiment_daily（X 走 tw_tweet_ticker⋈tw_tweet_sentiment）
│   │   ├── retail_volume.py    #   ★整体散户 每日讨论度 rollup：同口径计数 → 本地 retail_volume_daily
│   │   ├── retail_newcomers.py #   ★整体散户 每日新增散户 rollup：各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube) → 本地 retail_newcomers_daily
│   │   ├── kol_newcomers.py    #   ★KOL 每日新增 KOL rollup：X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数 → 本地 kol_newcomers_daily
│   │   ├── overall_signals.py  #   ★整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON web/lib/data/overallData.json（读本地 daily 序列 + retail_sentiment_daily + /tmp/<ticker>_x6m.jsonl + /tmp/mt_* 技能缓存；_skill_map 复刻 gen_topinvestors 的 z。讨论方面/新叙事 2026-06-28 已下线）
│   │   └── translate.py       #   翻译成中文 *_zh 列（增量、幂等；走 SQLAlchemy/DATABASE_URL，云端本地通用）
│   └── data/                  #   随仓库的字典/样本（ticker_stoplist.txt, cn_hk_tickers.json, subreddits.yml, asia_targets.yml, global_targets.yml…）
│
├── web/                       # ③ Next.js 14 静态站
│   ├── app/
│   │   ├── layout.tsx         #   根布局（主题防闪烁 + 默认 OG/metadataBase）
│   │   ├── [lang]/            #   语言段（zh|en|ja|ko）：generateStaticParams（页面数 = locales × 各内页）
│   │   │   #   layout.tsx 仅 LocaleProvider；(app)/ = 侧栏壳(Sidebar/Topbar/MobileTabBar)，(marketing)/ = 无侧栏落地页壳
│   │   │   ├── page.tsx       #     ★总览看板（异动优先：异动与信号[跨区分歧/最看多/最看空 + gr_quote 价格异动] → 其次 市场总览[KPI/五区情绪/全球热度榜/跨区情绪热力]）
│   │   │   ├── tickers/ + tickers/[symbol]/   # 标的总览(可排序表 + 上方 **三个 KOL 排行榜** `KolRankBoards`：看多/看空=`getKolBullBearBoards`(kol_sentiment_daily 近14天 net 跨标的聚合、scope gr_ticker、top/bottom 5)、**情绪变化最大**=`getKolSentimentSwings`(同窗口劈前7/后7天，比**看多占比** n_bull/(bull+bear) 的 pp 变化、按 |Δ| top5；用占比非 net 以免被大票声量主导)) + 标的详情(★模块看板:个体观点·KOL[真实] + 异动/跨区视角/独有叙事/多空共识/风险温度/大家在等什么 — mock,多图表；海外信息差/最强反方/独立 YouTube 观点 模块已删)
│   │   │   ├── regions/ + regions/[region]/   # 区域总览(5 区卡+净情绪) + 区域详情(★模块看板:地区脉搏/热榜/异动/独有叙事/本区vs全球/性格画像/注意力轮动/今日引爆 — mock,多图表)
│   │   │   ├── search/        #     搜索（客户端 ticker/公司名模糊匹配）
│   │   │   ├── me(Profile) account(设置) login/ signup/ forgot-password/ reset-password/ auth/callback/  # 账号系统
│   │   │   ├── onboarding/    #     ★首登引导向导（沉浸式全屏；采集投资画像→写 user_profiles+自动追踪持仓；?edit=1 从设置复用）
│   │   │   ├── insights(管理员看板) status(routine 运维)
│   │   │   ├── lab/global-retail/ lab/asia-pulse/   # 旧 5 地区/亚洲原型（noindex；图表组件被新页复用）
│   │   │   └── lab/dev/      #     ★测试控制台（隐藏 noindex）：按钮即时触发/重置 onboarding·收藏·埋点·PWA 自测（DevConsole）
│   │   ├── sitemap.ts / robots.ts / not-found.tsx   # SEO + 404
│   │   └── icon.png           #   favicon
│   ├── lib/
│   │   ├── db.ts              #   ★构建期用 node:sqlite 读 ../data/dev.db；库缺失/查询失败→降级空（不崩 output:export）
│   │   ├── queries.ts         #   ★所有取数 SQL（getMindshare/getTrending/getPostDetail…）
│   │   ├── asiaQueries.ts      #   亚洲实验隐藏页取数（读 asia_* 表，try/catch 包裹：表缺失返回空不崩）
│   │   ├── globalQueries.ts    #   全球散户隐藏页取数（读 gr_* 表 + US 代表帖读现有 Reddit；try/catch 兜底）
│   │   ├── investorQueries.ts   #   投资者榜单取数（getInvestorBoard：X/YouTube/Reddit/雪球 各按作者聚合互动·播放→排名；缺表返回空）
│   │   ├── creatorQueries.ts    #   YouTube 作者页取数（getYoutubeCreator：单频道 ①标的判断 tickerJudgments[yt_analysis 立场/观点/论据/目标价 ⋈ price_daily 当时价→现在价+命中,含中性,按标的归组]/②代表性标的/③互动最高视频；getYoutubeChannelIds 供 generateStaticParams）
│   │   ├── i18n.ts + dictionaries/{zh,en,ja,ko}.ts # 多语（zh 为源，en/ja/ko 必须镜像同样的 key；UI 译，帖子内容 ja/ko 回退英文原文）
│   │   ├── supabase.ts / auth.ts / admin.ts    # Supabase 客户端 + 登录 + 管理员判定
│   │   ├── analytics.ts / searchCounts.ts      # 埋点 + 搜索榜（写 Supabase）
│   │   ├── favorites.ts                         # ★账户收藏/追踪：客户端读写 user_collections（RLS）
│   │   ├── profile.ts                           # ★用户投资画像：客户端读写 user_profiles（RLS）+ markOnboarded/isOnboarded（门禁标志走 user_metadata）
│   │   ├── instruments.ts                       # onboarding 持仓选择器的「广义标的」补集（ETF/杠杆反向/商品/加密/债券；个股来自 gr_ticker）
│   │   └── site.ts            #   SITE_URL（https://www.redditalpha.xyz）+ OG
│   ├── components/            #   UI 组件（Sidebar/Topbar/FeedCard/MarkdownLite… + auth/ favorites/ profile/ onboarding/ + OnboardingGate 首登门禁）
│   ├── next.config.mjs        #   output:export(仅生产) + cpus:1 串行导出 + images:unoptimized
│   └── public/               #   logo/og/avatars/communities（图片已压缩）
│
├── supabase/migrations/       # ② Supabase SQL 迁移（ticker_searches / analytics / user_collections / user_profiles 的表+RLS+RPC）
├── data/dev.db                # 本地 SQLite —— **Prismo 唯一真源**（含 gr_*/yt_*/kol_*；gitignore，部署用 git add -f 入库；**别 cloud-pull**）
├── dashboard.html             # ★Advanced Mindshare 实验单页：由 data/prismo_snapshot.db + 可选 forum_mindshare.json 预计算指标生成的纯 HTML 看板
├── experiments/
│   ├── build_mindshare_dashboard.py # 生成 dashboard.html（penetration/entropy/方向/集中度/热力图；若找到 equity1000/forum_mindshare.json，则合并 JP/KR/US/TW 论坛 region 对比）
│   └── exp1_fwd_return_probe.py     # 论坛信号 vs 前向收益的验证探针
├── Makefile                   # ★所有常用命令入口
├── .env / .env.example        # 凭据与配置（.env gitignore：QWEN/DEEPSEEK/DATABASE_URL…）
└── 文档：README / DEPLOY / CLOUD_DB / SUPABASE_AUTH / STRATEGY / ARCHITECTURE(本文)
```

---

## 5. 数据库 schema（14 主表 + 4 亚洲 + 3 全球散户 + 3 YouTube + 1 KOL 提炼 隔离表，`pipeline/common/models.py` 为单一真源；另有**仓库外加载**的 X `tw_*`，见表末行）

| 类别 | 表 | 说明 |
|---|---|---|
| 原始 | `subreddits` `authors` `posts` `comments` | 抓来的原始内容（含 `*_zh` 译文列、`market`；`posts.source` scan/author 区分实时舆情/作者库，`authors.crawled_at` 作者库增量标记） |
| 字典/抽取 | `ticker_meta` `mentions` | ticker 字典 + 帖子↔ticker 提及（含 confidence/method） |
| AI 分析 | `item_analysis` | ★逐帖打标结果（情绪/多空/质量/主题/双语摘要/per-ticker 论据），按 item_id 持久化 |
| 派生聚合 | `ticker_rollup` `market_mood` `trending` | 声量榜 / 市场情绪 / 异动（每次全量重算，可弃） |
| 叙事/简报 | `narratives` `narrative_tickers` `narrative_posts` `daily_briefs` | 主导叙事 + 每日简报 |
| 亚洲实验(隔离) | `asia_posts` `asia_analysis` `asia_ticker_summary` `asia_price` | 日韩本土散户帖(含 `sentiment`=flash 全量打分 + views/comments/images/verified) + 千问深析 + 每格汇总 + 日K价格（market `jp`/`kr`；与 us/cn 完全隔离，实时聚合/feed 一律不读，仅供隐藏看板） |
| 全球散户(隔离) | `gr_post` `gr_ticker_region` `gr_ticker` | 日韩台+中国大陆(雪球)爬精选跨区美股的散户帖(flash 打标 sentiment+stance) + 每 region×ticker 滚动(region `us`/`cn`/`jp`/`kr`/`tw`；**US 不入 gr_post，rollup 只读现有 Reddit**；CN 经浏览器过 WAF 导入) + 每 ticker 跨区派生(共识/分歧)。与 us/cn 主表 及 asia_* 均隔离，仅供隐藏页 /lab/global-retail |
| YouTube 观点(隔离) | `yt_video` `yt_analysis` `yt_ticker_summary` | 按标的近 24h、浏览量>1000 的**全语种**财经视频(YouTube Data API)→ Gemini **混合分析**(top N 原生看视频[画面+音频] + 其余字幕，受 8h/天视频预算)出 stance/sentiment/双语摘要 → 每标的浏览量加权汇总。**两条分析路径**：① `youtube-tag` Gemini 真看视频（最准；`--workers>1` 走**并发**真看，billing 解锁 8h/天后用，~8 线程；字幕本机 IP 抓不到→一律原生 video）；② `youtube-tag-text` **无配额兜底**：用**标题+简介**跑 DeepSeek(flash) 出双语观点(mode=`text`)，覆盖 Gemini 没看的长尾、**不占 `analyzed` 旗标**→ 日后 Gemini 仍能升级覆盖。**纳入站外当地分析者**(韩 슈퍼개미/日 testa/美 FinTube)。YouTube 数据经 `kolQueries.youtubeOps` 并入标的页**观点浏览器**(`OpinionExplorer`)；**原独立『YouTube 观点』模块已移除**(与浏览器重复，删 `YouTubeOpinions.tsx`+`youtubeQueries.ts`)；缺 key 回退 mock |
| YouTube 完整口播(隔离) | `yt_fulltext` | 视频「完整口播」：Gemini 真看视频→**只还原口播**(不描述画面)成有序段落 `{type:speech, speaker, text}`：**按语义分段**(3-6 句/段) + **行内 Markdown 划重点**(`**加粗**`关键结论/数据/标的、`*斜体*`转折，克制)；**多人(访谈/播客)每段标 `speaker`、独白留空**；剔赞助订阅VIP二维码宣传。列 content_zh(扁平**纯文本**,去 Markdown)+segments(JSON 有序带 Markdown)。前端 `YtFullContent.tsx`(被 `YtReader.tsx` 包裹，见 `yt_digest` 行)：行内 Markdown 渲染(`inline`/`RichText`)；单人→限行宽分段长文、多人→按说话人分回合对话排版；传入 chapters 时在对应 speech 段前插**章节标题+锚点 `data-ch`**。`youtube-fulltext --only/--per-ticker/--force/--no-frames`。⚠ 旧档 `visual` 段(关键帧)代码休眠、新提示不产出(下载/OCR 配方备查见 memory `project-youtube-fulltext`) |
| YouTube 投资者摘要+目录(本地派生) | `yt_digest` | YouTube 正文阅读容器 `YtReader.tsx` 的两个新模块：① **投资者摘要**(`summary_zh/en`：整段口播精华/话题 AI 提成 4-7 分点，放正文上方)；② **内容目录**(`chapters`=有序章节 `{t_zh,t_en,seg}`，seg=起始 **speech 段下标**→`YtFullContent` 据此埋 `data-ch` 锚点 + 章节标题；右侧目录点击→正文平滑滚到该段、折叠时先自动展开)。③ **正文默认折叠到 ~72vh(约一屏)**、`展开更多`/`收起`。`youtube_digest.py`/`make youtube-digest` 读 `yt_fulltext` 口播文本跑 **LOW 档(qwen-flash，不重看视频)**，校验 seg 单调/夹紧；增量、原生 DDL 不入 models.py、写本地；web `ytDigestMap`(kolQueries)→YtReader。需 `QWEN_API_KEY` |
| YouTube 判断参数(本地派生) | `yt_judgment` | 作者页「① 标的判断」每条判断的结构化 chip：从**已有** `yt_analysis`(summary+key_points+price_target)抽 `horizon_zh/en`(时间周期)·`target`(目标价，规整成 `$X`/`$X–Y`)·`key_levels_zh/en`(关键位置=支撑/阻力/突破位/形态/均线)。`youtube_judgment.py`/`make youtube-judgment` 跑 **LOW 档(qwen-flash，纯文本不重看视频)**，**只抽明说、缺则 null**(776 条 ~105 有值、target 69>price_target 60)；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest` 范式)；web creatorQueries `safe` LEFT JOIN(表缺失不影响)、目标价结构化优先于原始 `price_target`。需 `QWEN_API_KEY` |
| YouTube 作者×标的综合(本地派生) | `yt_creator_view` | 作者页「① 标的判断」**每标的综合**：把**同一博主对同一标的**的多条视频判断(已蒸馏 summary+key_points+stance)综合成 `stance`(整体立场)+`points_zh/en`(**3-5 条关键判断**，合并去重)。PK=(channel_id,ticker)。`youtube_creator_view.py`/`make youtube-creator-view` 跑 **LOW 档(qwen-flash，读已蒸馏文本不重看视频)**，**忠实综合不臆造**；增量、裸 sqlite3 写本地、不入 models.py(同 `yt_digest`/`yt_judgment` 范式)；web creatorQueries `safe` 按 channel 查、缺则回退最新一条判断的 key_points。让作者页每标的只显示一段综合而非铺开每条视频(原太繁杂)。635 对 0 失败。需 `QWEN_API_KEY` |
| KOL 提炼(隔离) | `kol_refined` | ★个体观点「AI 提炼+双语」：对 reddit/x/雪球 每标的每源 top-N 跑 DeepSeek(flash) → stance + **reason_zh·en**(为什么看多/看空) + **points_zh·en**(2-3 要点)，**提炼与翻译合一**(只 zh/en，ja/ko 前端回退 en)。PK source+item_id；`pipeline/analyze/kol_refine.py`/`make kol-refine`(增量、`--per-source`/`--only`/`--force`)。**标的页象限①「个体观点·KOL」** 用之替换照搬原文；YouTube 不入此表(复用 `yt_analysis`) |
| KOL 目标价+周期(隔离) | `kol_judgment` | ★个体观点的『目标价 + 操作周期』结构化抽取：对 reddit/x/雪球 每标的每源 top-N 跑 **LOW(qwen-flash)** 从**原帖**抽 `buy_price`/`sell_price`/`target_price`(各 nullable、区间取中点、原文留 `price_raw`) + `horizon_zh/en`(原话) + `horizon_bucket`(short/mid/long)。**只抽明说、反臆造**：prompt 喂**当前价锚点**(`_price_map`)剔数量级离谱者 + 拒 penny-pump/假设估值/相对幅度。PK 同 kol_refined (source,item_id,ticker)；`pipeline/analyze/kol_judgment.py`(复用 `kol_refine._load`)/`make kol-judgment`(增量、`--only`/`--force`)。**标的页『整体数据』散点(`TargetPricePanel`) + 『观点检索』正文提炼行** 用之；YouTube 不入此表(复用 `yt_judgment`)；web `kolQueries.judgmentMap` 再按现价 **0.2–5× band 二次剔噪**($1225 这类砍掉)。需 `QWEN_API_KEY` |
| KOL 视角分类(隔离) | `kol_viewpoint` | ★把已蒸馏观点(kol_refined + yt_analysis)用 DeepSeek(flash) 分到 **7 视角**(估值/业务成长/竞争/管理层/宏观/催化剂/资金盘面，1-3 个、首个为主、纯方向性/情绪→other)。PK 同 kol_refined (source,item_id,ticker)；`pipeline/analyze/kol_viewpoint.py`/`make kol-viewpoint`(增量、无明确观点预判 other 省调用)。供**标的页 KOL 模块的「视角」分类**(`ClassifiedOpinions.tsx` 视角 tab，只展示折线图选定那天的观点)，web 经 `kolQueries.viewpointMap` 挂到观点上 |
| KOL 每日净情绪(本地派生) | `kol_sentiment_daily` | ★折线图下方绿/红面积子面板的数据。每 (ticker,day) 跨平台把『提到该标的的帖子』按 **情绪 × ln(1+互动) × 相关性** 加权求和 = **无界净情绪 net**(>0 偏多/绿，<0 偏空/红，量纲随声量×情绪放大，Kaito 风)。源：本地 Reddit(`item_analysis.sentiment_score`)/雪球(`gr_post.sentiment`)/YouTube(`yt_analysis.sentiment`) + **云端 X**(`tw_tweet_topic`⋈`tw_tweet`⋈`tw_tweet_sentiment`，relevance 用关键词命中 `strong` 代理)。`kol_sentiment.py`/`make kol-sentiment`(整表重算；**原生 DDL 自建、不入 models.py**；混合读本地+云端、勿加 sqlite 覆盖)。⚠ `vertical_topic_metadata.json` 漏掉 NVDA/TSLA/AAPL/MSFT → 这些大票暂无 X 贡献。**⚠ `tw_tweet` 现已空 0 行** → `tw_tweet_topic⋈tw_tweet` 现返 0、net_x 是陈旧快照；散户版 `retail_sentiment` 已改走稳定的 `tw_tweet_ticker⋈tw_tweet_sentiment`，KOL 版待同样迁移 |
| KOL 每日讨论度(本地派生) | `kol_volume_daily` | ★『每日讨论度』堆叠条状子面板的数据。每 (ticker,day) 跨平台**计数**当天讨论该标的的帖子+视频：n_reddit(mentions⋈posts 去重)/n_xueqiu(gr_post)/n_youtube(yt_video) + **n_x = 直接数 `tw_tweet_ticker`**（**不 join `tw_tweet`**——后者是滚动窗口、tweet_id 漂移、join 丢行实测 0 命中；`tw_tweet_ticker` 才是稳定全量「推↔标的」链接，含 created_at、全历史；X 限 `gr_ticker` 全集），n_total=四者和。`kol_volume.py`/`make kol-volume`(整表重算；原生 DDL、不入 models.py；混合本地+云端、勿加 sqlite 覆盖) |
| 整体散户 每日净情绪(本地派生) | `retail_sentiment_daily` | ★KOL 模块切到「整体散户」时的绿/红面积数据。与 KOL 同形状(net + net_<平台>)，**人群口径=全量散户**、平台=X/Reddit/雪球/**Naver/YahooJP/PTT/Toss**(本土论坛)、**不含 YouTube**。加权 net += 情绪×相关性×**(1+ln(1+互动))**——`(1+…)` 基座让无互动数据的源(Yahoo JP 引擎不给赞/评)仍按「一帖一票」计入。**X 走稳定的 `tw_tweet_ticker`⋈`tw_tweet_sentiment`**（⚠ `tw_tweet` 现已空 0 行→KOL 版 net_x 已陈旧；散户版改用稳定链接表、代价是无逐帖互动→权重退化为基座 1.0）。`retail_sentiment.py`/`make retail-sentiment`(整表重算；原生 DDL、不入 models.py；混合本地+云端、勿加 sqlite 覆盖) |
| 整体散户 每日讨论度(本地派生) | `retail_volume_daily` | ★「整体散户」视图的堆叠条状数据。每 (ticker,day) 同口径**计数**：n_reddit/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source) + **n_x = 直接数 `tw_tweet_ticker`**，n_total=各平台和。`retail_volume.py`/`make retail-volume`(整表重算；原生 DDL、不入 models.py) |
| 整体散户 每日新增散户(本地派生) | `retail_newcomers_daily` | ★「整体散户」视图第三块『每日新增散户』堆叠条状。每 (ticker,day) 计**首次参与该标的讨论的去重作者数**(用户对该平台×标的最早出现日计 1)：n_reddit(posts⋈mentions + comments⋈父帖 mentions)/n_xueqiu/n_naver/n_yahoojp/n_ptt/n_toss(gr_post 按 source)，n_total=各平台和。**不含 X**(云端 `tw_tweet_ticker` 无作者列)/**YouTube**(创作者非散户)。`retail_newcomers.py`/`make retail-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py)。⚠ "数据集内首次"在数据窗起点偏高(Toss 仅 06-14 起) |
| KOL 每日新增 KOL(本地派生) | `kol_newcomers_daily` | ★「KOL」视图第三块『每日新增 KOL』堆叠条状。每 (ticker,day) 计**首次讨论该标的的去重作者数**，平台=**有身份/粉丝象征的 X / YouTube / 雪球**(不含 Reddit/匿名源)：n_x(`x_opinion` 按 handle)/n_youtube(`yt_video` 按 channel_id)/n_xueqiu(`gr_post` 按 author)，n_total=三者和。**X 用本地 `x_opinion`**(含作者)而非散户版云端 tw_tweet_ticker。`kol_newcomers.py`/`make kol-newcomers`(纯本地、整表重算；原生 DDL、不入 models.py) |
| YouTube 频道作者(本地) | `yt_channel` | YouTube 正文(OpinionExplorer 阅读面板)作者头像旁的**基础信息**：`subscriber_count`(粉丝)/`video_count`(视频)/`description`(简介)/`handle`(@)。`youtube_channels.py`/`make yt-channels` 用 **Data API `channels.list`**(part=snippet,statistics) 按 `yt_video.channel_id` 全集刷新(~540 频道/11 次调用、1 配额/次)；直接写本地(同 author_avatar)、不入 models.py；web `ytChannelMap`(kolQueries)→Reader。需 `YOUTUBE_API_KEY` |
| **X/Twitter(隔离·外部加载)** | `tw_tweet`(58万) `tw_kol` `tw_tweet_ticker` `tw_crawl_state` `tw_tweet_sentiment`(空) `tw_ticker_rollup`(空) + `tw_tweet_topic` | KOL 推文由**仓库外工具**灌入云端(14 天 bootstrap，**尚未打情绪/未聚合**)，**均不在 `models.py`**。`tw_tweet_topic` = `ingest/twitter_match.py` 的**关键词硬匹配**派生(无 AI；按 `vertical_topic_metadata.json` 每 topic 的 keyword_list 混合匹配 $cashtag/@handle/短语/单词，sigil 敏感+Unicode 分词)→ 仅留 **Stocks** vertical 并清掉「普通词」误报(Bullish→BLSH 等)；约 8.6 万 (推文,标的) 对 |

> 迁移只搬「原始+字典+AI 分析」这 7 张源表（贵、需长期保存）；派生表在云端用 `make rollup` 等重算。
> 亚洲实验 4 表 + 全球散户 3 表 + YouTube 3 表都在 `ALL_TABLES`（`cloud-pull` 会快照），但**不在** `sync.SOURCE_TABLES`；`make asia` / `make gr` / `make youtube` 写当前 `DATABASE_URL`（本地验证用 `DATABASE_URL='sqlite:///./data/dev.db'` 覆盖，勿对云端跑建表 DDL）。
> **X 的 `tw_*` 不同**：由仓库外工具直接写云端，**不在 `models.py`/`ALL_TABLES`**（故 `cloud-pull` 不快照、网站构建也不读）；`tw_tweet_topic` 由 `twitter_match.py` 用原生 DDL 自建。重跑匹配：`pipeline/.venv/bin/python -m pipeline.ingest.twitter_match`（整表重算，幂等）。

---

## 6. 大模型档位（`pipeline/common/llm.py` 为路由真源）

| 档位 | 用途 | 当前 provider |
|---|---|---|
| **HIGH** | 逐帖投资打标（思考模式，全站分析大脑，token 大头） | 通义千问 `qwen3.7-plus` |
| **MID** | 叙事聚类 / 每日简报 / 正文重排版 | DeepSeek `deepseek-v4-pro` |
| **LOW** | 翻译 + KOL 提炼/视角/论点综合（走量） | 通义千问 `qwen-flash`（原 DeepSeek flash；2026-06 DeepSeek 余额耗尽 → 切千问，`QWEN_MODEL_LOW` 可改回）。**故 KOL 三步现需 `QWEN_API_KEY`，非 DeepSeek** |
| **VIDEO**（独立 provider，不经 llm.py 档位路由） | YouTube 视频理解(画面+音频) + 字幕文本总结（「YouTube 观点」模块） | Gemini `gemini-3.5-flash`（`common/gemini.py`；`file_data` 直传 YouTube URL，preview 免费/限 8h/天） |

改模型只动 `llm.py` 路由表（Gemini 例外：在 `common/gemini.py` 由 `youtube_analyze` 直接调用）。缺 key 时各环节回退 mock 启发式，不崩。

---

## 7. 常用命令（Makefile）

| 命令 | 作用 |
|---|---|
| `make daily` | 分析过去 24h（抓取+AI 打标+聚合+翻译），直接写 `DATABASE_URL`（云端）；含作者库爬取 |
| `make crawl-authors` | 单独跑作者库：爬实力榜 Top 作者历史帖（DeepSeek 粗筛→千问深析）。需 DeepSeek key |
| `make analyze-qwen` | 真实千问逐帖打标 + 重算聚合 |
| `make asia` | 亚洲散户舆情实验：爬日(Yahoo)/韩(Naver)本土板 + 真实 AI 分析（千问逐帖 + DeepSeek 汇总）。`make asia-mock` 为零成本版 |
| `make gr` | 全球散户五地区看板：日韩台爬精选跨区美股 + DeepSeek flash 打标 + 跨区滚动(US 读现有 Reddit)。隐藏页 /lab/global-retail。CN(雪球)走 `gr-xueqiu`(收浏览器过 WAF 的导出 JSON) |
| `make toss` | Toss(토스증권) 종목 커뮤니티评论爬取 → `gr_post(source='toss',region='kr')` + `gr-tag` 打标。逆向 Web API `wts-cert-api.tossinvest.com/api/v4/comments`(subjectType=STOCK&subjectId={code}&commentSortType=RECENT，**无需登录**、游标 `lastCommentId` 翻页、每页 11 条)；标的映射 `ingest/toss.py` 的 `TOSS_STOCKS`(先 PLTR=US20200930014)。`--days/--only/--max-pages`。**本地跑须 `DATABASE_URL='sqlite:///./data/dev.db'`**。落库后跑 `retail-sentiment`/`retail-volume`。出站 `make site` |
| `make youtube` | YouTube 观点：按标的搜近 24h、浏览量>1000 的全语种视频(`youtube-crawl`) + Gemini 混合分析(`youtube-tag`：top N 原生看视频+其余字幕)→ 标的页「YouTube 观点」模块。需 `YOUTUBE_API_KEY`+`GEMINI_API_KEY`；无 key 验证 `make youtube-mock`(多语种样本)。**全量真看视频**(billing)：`youtube-tag --workers 8`(并发)；**无配额兜底**：`youtube-tag-text`(标题+简介→DeepSeek 双语，mode=text) |
| `make yt-channels` | YouTube 频道作者基础信息(粉丝数/视频数/个人简介/@handle) → 本地 `yt_channel`(供 YouTube 正文作者头像旁展示)。Data API `channels.list`(part=snippet,statistics)；需 `YOUTUBE_API_KEY`。整表刷新(~540 频道)。出站 `make site` |
| `make youtube-digest` | YouTube 完整口播 → 「投资者摘要」+「内容目录(章节)」→ 本地 `yt_digest`。读 `yt_fulltext` 口播文本跑 LOW 档(qwen-flash，不重看视频)；增量(`--force` 重跑、`--only` 指定 video_id)；需 `QWEN_API_KEY`。先跑 `youtube-fulltext`。出站 `make site` |
| `make youtube-judgment` | 作者页「① 标的判断」结构化参数：从 `yt_analysis` 观点/论据抽 时间周期/目标价/关键位置 → 本地 `yt_judgment`。LOW 档(qwen-flash，纯文本不重看视频)；增量(`--force` 重抽、`--only` 指定 ticker、`--workers`)；只抽明说不臆造、多为 null；需 `QWEN_API_KEY`。出站 `make site` |
| `make youtube-creator-view` | 作者页「① 标的判断」每标的综合：把同一博主对同一标的的多条视频判断综合成 整体立场+几点关键判断 → 本地 `yt_creator_view`。LOW 档(qwen-flash，读已蒸馏文本不重看视频)；增量(`--force`/`--only` ticker/`--workers`)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-judgment` | KOL 目标价+操作周期：从 reddit/x/雪球 **原帖**抽 买入/卖出/目标价(prompt 现价锚点剔噪)+周期 → 本地 `kol_judgment`。LOW(qwen-flash)；增量(`--only`/`--force`)；只抽明说、反臆造；先跑 `kol-refine`(复用其候选池)；需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-refine` | KOL 个体观点提炼：reddit/x/雪球 每标的每源 top-N 跑 DeepSeek(flash) → `kol_refined`(为什么看多/看空 + 2-3 要点，zh/en)。标的页象限①「个体观点·KOL」展示提炼而非照搬原文。增量；`pipeline.manage kol-refine --per-source/--only/--source/--force`。需 `DEEPSEEK_API_KEY` |
| `make kol-viewpoint` | KOL 观点视角分类：对已蒸馏观点(`kol_refined`+`yt_analysis`) 跑 DeepSeek(flash) → `kol_viewpoint`(7 视角 1-3 个)。供标的页 KOL 模块「按视角」视图。增量；先跑 `kol-refine` 再跑本目标；`--only/--force`。需 `DEEPSEEK_API_KEY` |
| `make tw-sentiment` | X 推文情绪打分：`tw_tweet_topic` 命中的 ~5.4 万推文 flash 批量打 -1..1 → **云端** `tw_tweet_sentiment`。⚠ 别加 sqlite 覆盖。增量。需 flash key。供 `kol-sentiment` |
| `make kol-sentiment` | KOL 每日净情绪 rollup：跨平台 情绪×ln(1+互动)×相关性 → 本地 `kol_sentiment_daily`(折线图下方绿/红面积)。⚠ **不加** sqlite 覆盖(脚本自 hardcode 本地+从 .env 读云端拿 X)。先跑 `tw-sentiment`。出站 `make site` |
| `make kol-volume` | KOL 每日讨论度 rollup：跨平台帖子/视频**计数** → 本地 `kol_volume_daily`(折线图下方条状图)。X **直接数 `tw_tweet_ticker`**(不 join tw_tweet)。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-sentiment` | 整体散户 每日净情绪 rollup → 本地 `retail_sentiment_daily`(KOL 模块切到「整体散户」时的绿/红面积)。全量散户+本土论坛(Naver/YahooJP/PTT/Toss)、不含 YouTube；X 走 `tw_tweet_ticker`⋈`tw_tweet_sentiment`。⚠ **不加** sqlite 覆盖。先跑 `tw-sentiment`。出站 `make site` |
| `make retail-volume` | 整体散户 每日讨论度 rollup → 本地 `retail_volume_daily`(「整体散户」视图的条状图)。同口径计数。⚠ **不加** sqlite 覆盖。出站 `make site` |
| `make retail-newcomers` | 整体散户 每日新增散户 rollup → 本地 `retail_newcomers_daily`(「整体散户」视图第三块条状图)。各平台首次参与该标的讨论的去重作者数(Reddit 发帖+评论 / 5 论坛；不含 X/YouTube)。**纯本地、无需云端**。出站 `make site` |
| `make kol-newcomers` | KOL 每日新增 KOL rollup → 本地 `kol_newcomers_daily`(「KOL」视图第三块条状图)。X(x_opinion)/YouTube(yt_video)/雪球(gr_post) 首次讨论该标的的去重作者数。**纯本地、无需云端**。出站 `make site` |
| `make overall-signals` | 整体数据『异动归因 + 聪明钱↔散户分歧』(仅 KOL，qwen-flash) → 构建期 JSON `web/lib/data/overallData.json`(异动金 ⚑ 标记+AI 归因 / 技能加权 KOL vs 散户分歧线)。读本地 daily + `retail_sentiment_daily` + `/tmp/<ticker>_x6m.jsonl` + `/tmp/mt_*` 技能缓存。`TICKER=XXX make overall-signals`(默认 PLTR)。需 `QWEN_API_KEY`。出站 `make site` |
| `make kol-translate` | KOL 原帖**完整忠实翻译**(逐句、不压缩) → `kol_refined.trans_zh·en`。供观点浏览器卡片/阅读面板的「译」选项。只译已展示项、增量；与提炼解耦可独立重跑；`--source/--per-source/--since-days/--only/--force`。需 `QWEN_API_KEY`。本地测试加 `DATABASE_URL=sqlite:///./data/dev.db` 直写 `dev.db` |
| `make kol-relevance` | KOL **相关性打分** 0-100(越高=越是在讲这只票，区分「深度分析」vs「顺带列入名单」) → 隔离表 `kol_relevance`(覆盖 reddit/x/雪球+youtube)。供观点浏览器默认『相关度降序』排序(不做筛选)。增量、可独立重跑；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY`。本地测试同上 |
| `make kol-quality` | KOL **帖子质量打分** 0-100(内容含金量：实质分析/数据/逻辑 vs 口号/喊单/灌水；**与标的无关**，按 source+item 去重) → 隔离表 `kol_quality`。供观点浏览器『只看高质量』开关(≥65)。覆盖 reddit/x/雪球+youtube；增量；`--only/--force/--per-source/--no-youtube`。需 `QWEN_API_KEY` |
| `make mindshare-dashboard` | 从 `data/prismo_snapshot.db` 生成根目录 `dashboard.html`：单文件实验面板，展示 penetration/entropy/量加权方向/集中度/跨市场与社区热力等 Advanced Mindshare 移植指标；若存在 `/Users/tongzheng/equity1000/forum_mindshare.json` 或 `FORUM_MINDSHARE_JSON` 指定文件，会额外嵌入 JP Yahoo / KR Naver / US Reddit / TW PTT 的 ticker×region 与 region×ticker 对比 |
| `make rollup / mood / trending / narratives / brief` | 单独重算各聚合 |
| `make cloud-init` | 一次性迁移：建表 + 上传本地源数据 + 云端重算派生表 |
| `make cloud-push` | 把本地源数据增量上传到云端（redditalpha 用；Prismo 一般不需要） |
| `make cloud-pull` | ⛔ **默认拒绝**（会用「只有 Reddit 核心」的云端覆盖本地、抹掉 Prismo 独有的 gr_*/yt_*/kol_*）。确需重建：`make backup-db && FORCE=1 make cloud-pull` |
| `make backup-db` | 备份 `data/dev.db` → `data/dev.db.bak-<时间戳>`（改数据前先跑） |
| `make site` | 构建静态站 `web/out/`（读**本地 dev.db**；需 **Node 22**） |
| `make site-cloud` | **现等同 `make site`**（Prismo 以本地为真源、不再 cloud-pull；保留名字防误清） |
| `make stats` | 打印库内统计 |
| `make demo` | 一键离线全流程（样本+mock，无需 key） |

---

## 8. 构建 & 部署

1. `nvm use 22`（**必须 Node 22**；Node 23 + 实验 SQLite 会让构建被系统 SIGKILL）。
2. `make site-cloud`（从云端拉数据 + `next build` → `web/out/`，~6500 页、cpus:1 串行 ~2–3 分钟）。
3. 部署 `web/out/` 到静态托管（自定义根域名 www.redditalpha.xyz）。详见 `DEPLOY.md`。

---

## 9. 重要约定 / 易踩坑

- **构建用 Node 22**（见上）。若构建报 `Cannot find module for page /_not-found`：先 `rm -rf web/.next web/out` 再构建（残留进程会锁住 .next）。
- **多语字典**：`dictionaries/zh.ts` 是源（`Dictionary = typeof zh`），`en.ts`/`ja.ts`/`ko.ts` 必须镜像完全相同的 key（`npx tsc --noEmit` 会强校验）。新增 locale 只需在 `i18n.ts` 的 `locales`/`isLocale`/`DICTS` 三处登记 + 加 `LanguageSwitcher` 选项；路由/sitemap 自动随 `locales` 扩展。帖子内容只有 `*_zh` 译文，故 ja/ko 渲染时回退英文原文。
- **密钥不入库**：`.env` / `web/.env.local` 已 gitignore；含 `QWEN_API_KEY`/`DEEPSEEK_API_KEY`/`DATABASE_URL`(含密码)/Supabase anon key 等，切勿提交或泄露。
- **回到纯本地**：`.env` 的 `DATABASE_URL` 改回 `sqlite:///./data/dev.db` 即可。
- **管线所有步骤必须走 SQLAlchemy（`common/db.py` 的 engine），不要裸 `sqlite3.connect`**：否则 `DATABASE_URL` 指向云端时会把结果写进本地文件、云端拿不到。`translate.py` 曾因此漏译（已修）；`format_posts.py` / `seed_demo_zh.py` 仍是裸 sqlite3，仅本地/ demo 用，勿放进 daily 云端流程。
- **管理员看板**（`/insights`）：前端只是 UX 门槛，真正鉴权在 Supabase 端（`is_admin()` 校验 JWT 邮箱）。
- **待办（省 token）**：千问/DeepSeek 的系统提示词每次逐帖重发，未确认是否走缓存计费；可启用上下文缓存。
