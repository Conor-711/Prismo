import type { Config } from "tailwindcss";

// 设计 tokens：暖中性底 + Reddit 橙 + 金属(金/银/铜)。
// 大部分底色/文字/边框走 CSS 变量(见 globals.css 的 :root / html.light)，
// 以便用 .light 类切换「白天模式」；alpha 用 <alpha-value> 以保留 /opacity 工具类。
const v = (name: string) => `rgb(var(${name}) / <alpha-value>)`;

const config: Config = {
  darkMode: "class",
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // 可切换主题的底色族
        ink: v("--c-ink"), // 页面底色
        surface: v("--c-surface"), // 导航 / 顶栏
        card: v("--c-card"), // 卡片基底
        elevated: v("--c-elevated"),
        line: v("--c-line"), // 发丝边
        navy: v("--c-navy"), // 兼容旧引用
        cream: v("--c-cream"), // 主文字（深色=米白 / 浅色=近黑）
        gold: v("--c-gold"), // 高信号（浅色下转深金以保可读）
        silver: v("--c-silver"),
        // 品牌 / 语义色：两套主题通用，固定值
        reddit: "#FF4500", // Reddit 橙红 (OrangeRed) = 品牌主色 / upvote / 热度 / CTA
        amber: "#FF4500", // 沿用既有 amber 类名 = Reddit 橙
        downvote: "#7193FF",
        bull: "#24B47E", // 看多 / 上涨
        bear: "#F0556E", // 看空 / 下跌
        bronze: "#C99B70", // 金属铜
        // 中性灰阶走变量：浅色模式下整体反向，文字保持可读
        neutral: {
          50: v("--n-50"),
          100: v("--n-100"),
          200: v("--n-200"),
          300: v("--n-300"),
          400: v("--n-400"),
          500: v("--n-500"),
          600: v("--n-600"),
          700: v("--n-700"),
          800: v("--n-800"),
          900: v("--n-900"),
          950: v("--n-950"),
        },
      },
      fontFamily: {
        display: ["var(--font-sora)", "ui-sans-serif", "sans-serif"],
        sans: ["var(--font-inter)", "ui-sans-serif", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
    },
  },
  plugins: [],
};

export default config;
