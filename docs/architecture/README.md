# Architecture Docs

本目录把根目录 `ARCHITECTURE.md` 拆成可维护的专题文档。根文档仍是项目活地图；本目录负责记录长期边界、模块归属和新增功能时的落点规则。

## 阅读顺序

1. `00-overview.md`：系统总览和当前真源。
2. `01-frontend.md`：Next.js 前端模块边界。
3. `02-pipeline.md`：Python 数据管线模块边界。
4. `03-data-model.md`：数据库、派生表、快照和 schema 规则。
5. `04-platform-adapters.md`：新增平台时的适配器规范。
6. `05-smart-account.md`：Smart Account 的实现边界。
7. `06-deployment.md`：构建、数据快照和部署路径。
8. `08-development-rules.md`：后续新功能开发落点、禁止落点、常见场景和验证清单。
9. `09-ios.md`：iOS 主客户端、SwiftUI 边界、API 消费和发布规则。
10. `07-conventions.md`：命名、目录和维护约定。

## 维护原则

- `ARCHITECTURE.md` 只放系统地图、关键事实和入口链接。
- 本目录放稳定边界和长期规范，不记录临时排障细节。
- 需求实现时，如果新增目录、表、命令、平台或数据流，必须同步更新对应专题文档。
- 当前代码仍在迁移期；专题文档描述的是目标边界和新增代码必须遵循的规则。
