// 站点绝对地址（用于分享链接与 Open Graph 卡片）。部署域名不同就改 NEXT_PUBLIC_SITE_URL。
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL || "https://www.redditalpha.xyz").replace(/\/+$/, "");
export const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH || "";
// 默认 OG 卡片图（建议放一张 1200×630 的 /og.png；缺省回退到 logo）。
export const OG_IMAGE = `${SITE_URL}${BASE_PATH}/og.png`;
