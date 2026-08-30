# Onboarding Feature

首登引导按“流程编排”和“步骤展示”分层：

- `web/components/onboarding/OnboardingFlow.tsx` 保留兼容入口，负责登录态、画像读写、步骤状态、拖拽交互和提交编排。
- `components/OnboardingSteps.tsx` 只负责各步骤、基础选择控件和欢迎/完成状态的展示，不直接读写服务端数据。

新增问题时，数据定义和提交字段先进入画像契约；步骤 UI 放在 feature 内，跨步骤状态仍由
`OnboardingFlow` 单点管理。不要在步骤组件中新增 Supabase、路由或持久化调用。
