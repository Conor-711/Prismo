# 名人与机构持仓来源：SEC 13F

## 范围与归因

`python -m pipeline.jobs.institutional_holdings` 从 SEC EDGAR 的申报历史和原始 XML 表格生成季度持仓快照。名人是展示身份，不是法律申报人：

2026-09-29 的已验证导出有 18 位名人和 33 家机构；注册表另有一位等待人工核对修订申报的机构，不计入发布数量。以下是初始主体及关键人物映射；完整名单以 `pipeline/domain/institutional_holdings/registry.py` 和导出 manifest 为准。

| 展示身份 | 申报主体 | CIK | 说明 |
| --- | --- | ---: | --- |
| Michael Burry | Scion Asset Management, LLC | 1649339 | 不等于 Burry 的个人账户；最后可见 13F 可能很旧 |
| Warren Buffett | Berkshire Hathaway Inc. | 1067983 | Berkshire 的全部申报持仓不等于 Buffett 个人决策 |
| Bill Ackman | Pershing Square Inc. | 2026053 | Pershing Square Capital Management LP 的 13F-NT 指向这一申报主体；不是 Ackman 的个人账户 |
| Cathie Wood | ARK Investment Management LLC | 1697748 | 与 ARK 机构身份共享同一份 13F；不是 Wood 的个人交易 |
| David Tepper | Appaloosa LP | 1656456 | Appaloosa 的季末持仓，不是 Tepper 的个人交易 |
| Daniel Loeb | Third Point LLC | 1040273 | Third Point 的季末持仓，不是 Loeb 的个人交易 |
| Ken Griffin | Citadel Advisors LLC | 1423053 | 与 Citadel 共享申报，不是个人交易 |
| Chase Coleman | Tiger Global Management LLC | 1167483 | 与 Tiger Global 共享申报，不是个人交易 |
| Philippe Laffont | Coatue Management LLC | 1135730 | 与 Coatue 共享申报，不是个人交易 |
| Stanley Druckenmiller | Duquesne Family Office LLC | 1536411 | Duquesne 的申报，不是个人交易 |
| Seth Klarman | Baupost Group LLC | 1061768 | Baupost 的申报，不是个人交易 |
| David Einhorn | DME Capital Management LP | 1489933 | 现行申报主体；旧 Greenlight Capital Inc. 申报停在 2023 年 |
| Steve Cohen | Point72 Asset Management LP | 1603466 | Point72 的申报，不是个人交易 |
| Ole Andreas Halvorsen | Viking Global Investors LP | 1103804 | Viking 的申报，不是个人交易 |
| Paul Singer | Elliott Investment Management LP | 1791786 | Elliott 的申报，不是个人交易 |
| Li Lu | Himalaya Capital Management LLC | 1709323 | Himalaya 的申报，不是个人交易 |
| Nelson Peltz | Trian Fund Management LP | 1345471 | Trian 的申报，不是个人交易 |
| Cliff Asness | AQR Capital Management LLC | 1167557 | AQR 的部分组合申报，不是个人交易 |
| Bridgewater Associates | Bridgewater Associates, LP | 1350694 | 机构身份 |
| Citadel Advisors | Citadel Advisors LLC | 1423053 | 机构身份；优先采用完整重述修订版 |
| ARK Investment Management | ARK Investment Management LLC | 1697748 | 机构身份 |
| Tiger Global Management | Tiger Global Management LLC | 1167483 | 机构身份 |
| Renaissance Technologies | Renaissance Technologies LLC | 1037389 | 机构身份 |
| Coatue Management | Coatue Management LLC | 1135730 | 机构身份 |

新增机构还包括 Scion、Berkshire、Pershing Square、Appaloosa、Third Point、Greenlight/DME、Baupost、Duquesne、Point72、Viking、Elliott、Himalaya、Soros、D. E. Shaw、Millennium、Two Sigma、AQR、Lone Pine、Trian、Glenview、Maverick、Balyasny、Marshall Wace、Select Equity、Capital Research Global、PRIMECAP 和 Dodge & Cox。Farallon 的最新 13F-HR/A 是追加持仓修订，自动解析器不把它误当完整重述；通过人工合并核验前不发布。

Jim Cramer 不在本持仓来源内。他的 CNBC Investing Club Charitable Trust 实时持仓/交易提醒是会员产品，不能把它当作公开 13F，也不抓取付费内容。将来可单独以授权的公开言论源接入，并与季度持仓数据明确分开。

## 运行

SEC 要求自动化访问标明真实联系信息。使用项目运营方真实邮箱，不把它硬编码在代码里：

```bash
export BSMART_OFFICIAL_CONTACT='your-real-contact@example.com'
uv run --offline python -m pipeline.jobs.institutional_holdings
uv run --offline python -m pipeline.jobs.institutional_holdings --subject bill-ackman
uv run --offline python -m pipeline.jobs.institutional_holdings --subject cathie-wood --reuse-verified-filing-from ark
```

输出在 `data/exports/institutional_holdings/`，每个主体一个 JSON，另有 `manifest.json`。抓取严格限制单次请求数和频率；某个主体失败时保留上次成功快照，并在 manifest 中标 `error`，绝不将旧数据标成新的成功抓取。原始 XML 不留存，避免无谓占用磁盘。适合在 13F 截止日之后每日运行，而不是每三小时运行；2026 年第三季度申报截止日为 2026-11-16。
单主体运行仅更新该主体，manifest 保留其他主体上次检查结果，并以各自的 `checkedAt` 区分新旧。
共享 CIK 的展示身份只请求同一份申报一次；`--reuse-verified-filing-from` 可从本地已核验的同 CIK 快照生成另一个身份，保留原 `checkedAt`，不伪称新抓取。缺少快照的新增主体不会进入 App 内容。所有新主体首次抓取前必须配置真实 `BSMART_OFFICIAL_CONTACT`；刷新失败会保留旧快照并标记错误。每个季度申报之后再更新，不适合每三小时抓取。

## 输出语义

- `title`/`kind` 是产品展示身份，`filerName`/`filerCik`/`filingUrl` 是事实来源；前端必须同时能看到申报主体和季度日期。
- Cathie Wood 与 ARK 机构页引用同一份报告，不能将两个展示入口计为两个独立交易来源。ARK 对其投资决策的职责说明见其官网；其他人物映射分别依据申报主体及管理人公开资料核对。
- `periodOfReport` 是季末持仓日期，`filedAt` 是文件公开日期，不能当作买入/卖出日期。
- `holdings[].reportedValueUsd` 是 13F 表格中按美元申报的季末价值；`reportedShares` 是数量，不是成本或今日余额。
- `changes` 只比较两份连续、完整、可比的申报表的报告数量，分类为“新增披露/不再披露/申报数量增减”，不是确认的交易，也不能据此直接算个人胜率或跟投收益。
- `13F-HR/A` 仅自动接受完整重述；“新增持仓”修订须人工处理。`13F-NT` 是指向其他管理人的通知，绝不是零持仓。`13F COMBINATION REPORT` 只提供部分持仓，与完整报告不做数量差计算。
- 13F 不覆盖所有资产、空头、非 13(f) 证券或盘中交易。`stale` 或 `newer_notice_without_holdings` 必须在产品中显示，不应回退成“当前持仓”。
- CUSIP 只作为内部匹配键，不直接展示或再分发；公开产品需另行确认证券标识映射及相应许可。

这一步建立的是可审计的数据层来源，未将季报变化自动发布成 App 的实时观点、交易信号或个人业绩排行。面向用户的发布需要单独的主体映射与内容审核。

## 官方参考

- [SEC EDGAR API](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [SEC 13F FAQ、披露范围与申报期限](https://www.sec.gov/rules-regulations/staff-guidance/division-investment-management-frequently-asked-questions/frequently-asked-questions-about-form-13f)
- [SEC 公平访问速率](https://www.sec.gov/filergroup/announcements-old/new-rate-control-limits)
- [SEC 13F 表格](https://www.sec.gov/pdf/form13f.pdf)
- [Pershing Square Capital Management LP 的 13F-NT](https://www.sec.gov/Archives/edgar/data/1336528/000117266126003777/0001172661-26-003777-index.html)
- [ARK 关于 Cathie Wood 的职务和投资决策职责](https://www.ark-invest.com/board-of-directors)
- [Appaloosa 13F 申报](https://www.sec.gov/Archives/edgar/data/1656456/000165645626000003/0001656456-26-000003-index.html)
- [Third Point 管理团队](https://www.thirdpoint.com/)
- [DME Capital Management 最新 13F](https://www.sec.gov/Archives/edgar/data/1489933/000117266126003786/0001172661-26-003786-index.html)
- [Citadel 关于 Ken Griffin 的职务](https://www.citadel.com/who-we-are/leadership/kenneth-c-griffin/)
- [Tiger Global 关于 Chase Coleman 的职务](https://www.tigerglobal.com/chase-coleman)
- [Himalaya Capital 关于 Li Lu 的职务](https://www.himcap.com/)
