# Smart Voice Feature

`web/features/smart-voice` 承接跨页面 Smart Voice 展示模块。

归属原则：

- SV 算法、作者分、标的分、组合分的产品展示归属本 feature。
- SV 原始计算与 pipeline 规则归属 `pipeline/domain` / `docs/architecture/05-smart-voice.md`。
- 平台头像、来源配色等通用展示基础件从 `web/shared/market/kolPresentation.tsx` 引入。

当前已迁移：

- `components/SmartVoiceModules.tsx`
- `components/SmartVoiceWorkspace.tsx`
- `components/SmartVoiceWorkspacePanels.tsx`
- `svMock.ts`
- `svMock/types.ts`
- `svMock/constants.ts`
- `svMock/generated.ts`
- `svMock/scoring.ts`
- `index.ts`
