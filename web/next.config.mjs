/** @type {import('next').NextConfig} */
// 部署到 GitHub Pages 项目页（子路径）时设 NEXT_PUBLIC_BASE_PATH=/<repo>；
// 部署到根域名（Netlify/Cloudflare/Vercel/自定义域名）留空即可。
const basePath = process.env.NEXT_PUBLIC_BASE_PATH || "";

const nextConfig = {
  reactStrictMode: true,
  // 静态导出：构建期读 DB 生成快照，产物在 out/，可部署到任何静态托管。
  // 静态导出仅用于生产构建(make site/make serve)；dev 用普通服务端模式，
  // 否则 output:export + 动态路由(/ticker/[symbol]) 在 next dev 下会误报缺 generateStaticParams。
  output: process.env.NODE_ENV === "production" ? "export" : undefined,
  trailingSlash: true,
  images: { unoptimized: true },
  basePath,
  assetPrefix: basePath || undefined,
  // 静态导出页数很多(数千页)时，并行 worker 偶发 "Cannot find module for page X.js"
  // 的导出竞态。串行化生成(单 worker)虽稍慢，但消除该 flaky 错误，保证 out/ 完整。
  experimental: { workerThreads: false, cpus: 1 },
};

export default nextConfig;
