# Railway 部署：一镜像内跑完整管线(真实数据+样本兜底)→ 构建静态站 → 在 $PORT 提供服务。
# 用明确的 Dockerfile，避免 Railway Nixpacks 对 Python+Node 混合仓库识别失败。
FROM node:22-slim

# Python（管线用）
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV DATABASE_URL=sqlite:///./data/dev.db \
    REDDIT_USER_AGENT="redditalpha/0.1 (railway build)"

# ---- 依赖层（利于缓存）----
COPY pipeline/requirements.txt pipeline/requirements.txt
RUN python3 -m venv /venv && /venv/bin/pip install --no-cache-dir -r pipeline/requirements.txt

COPY web/package.json web/package-lock.json* web/
RUN cd web && npm install --no-audit --no-fund

# ---- 源码 ----
COPY . .

# ---- 数据集：直接使用仓库内提交的 data/dev.db（不再在镜像内 scrape/mock 重生成）----
# 该库由本地 `make daily` 产出：千问逐帖真实分析 + DeepSeek 中文翻译 + 评论快照，
# 已随上面的 COPY . . 进入镜像（.gitignore / .dockerignore 已对 data/dev.db 开例外）。
# 这样线上 = 本地。更新线上：本机重跑 `make daily` → 重新提交 data/dev.db → push 触发 Railway 重建。
# 注：dev.db 已含完整 schema + us/cn 双市场聚合 + ticker_meta（保证 /cn/ticker generateStaticParams 非空）。

# ---- 前端公开变量（NEXT_PUBLIC_*）----
# Next 在「构建期」把这些值内联进静态导出包；运行期再设也没用（静态文件已生成）。
# 故必须在 npm run build 之前注入。Railway 会把「同名的服务变量」作为 build arg 传给 Docker，
# 因此只要在 Railway 项目里设置下面这些变量，线上 /insights 的 Supabase 就会「已配置」。
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_ADMIN_EMAIL
ARG NEXT_PUBLIC_SITE_URL
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_ADMIN_EMAIL=$NEXT_PUBLIC_ADMIN_EMAIL \
    NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL

# ---- 构建静态站（build 脚本已含 NODE_OPTIONS=--experimental-sqlite）----
RUN cd web && npm run build

ENV PORT=8080
EXPOSE 8080
# 用 Node 静态服务托管 web/out（原生读 process.env.PORT，不依赖 shell 展开）
CMD ["node", "server.mjs"]
