# 把数据搬上云端（Supabase）

目标：让**每一条帖子的数据与分析真正存在云端**（Supabase = Postgres），而不是只躺在你笔记本的
`data/dev.db` 文件里。Supabase 成为数据的「家」（唯一真源）；本地只在构建网站时临时拉一份快照。

> 好消息：代码本来就支持 Postgres，Postgres 驱动也已装好。你只需提供 Supabase 连接串，跑两条命令。
> 你的数据约 15MB，**Supabase 免费档（500MB）绰绰有余**。

---

## 一、拿到 Supabase 连接串（只有你能做）

1. 打开 Supabase 控制台 → 你的项目 → **Project Settings → Database**。
2. 找到 **Connection string → URI**，复制那一串（形如
   `postgresql://postgres.xxxx:[YOUR-PASSWORD]@aws-0-xxx.pooler.supabase.com:6543/postgres`）。
   - 里面的 `[YOUR-PASSWORD]` 换成你的数据库密码（创建项目时设的；忘了可在同页 **Reset database password** 重置）。

> ⚠️ 安全：这串里含**数据库密码**，属于敏感凭据。请**你自己**粘贴进 `.env`，不要发给任何人。

## 二、填进 .env

打开仓库根目录的 `.env`（没有就 `cp .env.example .env`），把 `DATABASE_URL` 改成你的 Supabase 串：

```
DATABASE_URL=postgresql://postgres.xxxx:你的密码@aws-0-xxx.pooler.supabase.com:6543/postgres
```

（`postgres://` 开头也行，程序会自动转换并强制 SSL。）

## 三、一次性迁移：把现有 3700 条帖子搬上云端

```bash
make cloud-init
```

这条命令会：① 在 Supabase 自动建好 14 张表 → ② 把本地 `dev.db` 的**源数据**（帖子/评论/作者/AI
分析/提及/字典）上传到云端 → ③ 在云端重新算好榜单/情绪/异动/叙事/简报。
跑完去 Supabase 的 **Table Editor** 应能看到 `posts`、`item_analysis` 等表里有数据。

## 四、以后的日常

- **抓新数据 + AI 分析（直接写云端）**：
  ```bash
  make daily        # 因为 DATABASE_URL 指向云端，分析结果直接进 Supabase
  ```
- **出网站（从云端拉最新快照再构建）**：
  ```bash
  make site-cloud   # = 先从云端拉快照到本地 dev.db，再 npm run build
  ```
  然后照常部署 `web/out/`。

> 提示：构建请用 **Node 22**（`nvm use 22`），Node 23 会导致构建被系统杀掉。

---

## 常用命令小抄

| 命令 | 作用 |
|---|---|
| `make cloud-init` | 一次性：建表 + 上传现有数据 + 云端重算（迁移用） |
| `make cloud-push` | 把本地源数据再补传到云端（增量，安全可重复） |
| `make cloud-pull` | 从云端拉最新数据，覆盖本地 `data/dev.db` 快照 |
| `make site-cloud` | 拉云端快照 + 构建网站 |

## 想回到纯本地？
把 `.env` 的 `DATABASE_URL` 改回 `sqlite:///./data/dev.db` 即可，一切照旧。

## 说明
- 网站读取代码**完全没改**：它仍读本地 `data/dev.db`，只是这个文件现在是「从云端拉下来的快照」。
- 迁移只搬**源数据**（贵、需长期保存）；榜单/情绪/异动/叙事这些**派生结果**是廉价 SQL 重算，
  在云端重新生成即可，所以不用搬，也避免了自增 ID 冲突。
