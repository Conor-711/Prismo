# Author Contract

Author 是跨平台账号或创作者的标准引用对象。

## AuthorRef

观点流中的轻量作者引用：

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | Prismo 内部作者 ID，建议 `${source}:${platform_author_id}` |
| `source` | string | 平台 key |
| `platform_author_id` | string | 平台作者 ID |
| `name` | string | 展示名 |
| `handle` | string | 平台 handle，可为空 |
| `avatar_url` | string | 头像，可为空 |

## AuthorProfile

作者详情或 SV 需要的完整对象：

| 字段 | 类型 | 说明 |
|---|---|---|
| `followers_count` | number | 粉丝数，可为空 |
| `posts_count` | number | 平台总发帖数，可为空 |
| `verified` | boolean | 是否认证 |
| `verified_type` | string | 认证类型 |
| `badges` | string[] | 勋章、星计划、实盘认证等 |
| `description` | string | 作者简介 |
| `is_media` | boolean | 是否媒体/快讯/机构号 |
| `source_url` | string | 平台主页 |

## KOL 池约束

- 媒体号和个人投资者应分开标识，不能混进同一 KOL 排名池而不加区分。
- 没有作者唯一 ID 的平台，只能进入内容分析，不能进入正式 SV 作者排名。
- 粉丝数是 discovery 特征，不是 SV 的唯一评分标准。
