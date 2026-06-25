import type { Config } from "tailwindcss";

// 设计 tokens：近黑中性底 + 青绿信号 + 金属(金/银/铜)。
// 底色/文字/边框走 CSS 变量(见 globals.css 的 :root，暗色单主题，已停用白天模式)；
// alpha 用 <alpha-value> 以保留 /opacity 工具类。
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
        reddit: "#57D7BA", // QuiverQuant 青绿 = 品牌强调 / 链接 / 选中（沿用 reddit 类名免改）
        amber: "#57D7BA", // 沿用既有 amber 类名 = QuiverQuant 青绿
        brand: "#57D7BA", // 语义别名
        downvote: "#7193FF",
        bull: "#57D7BA", // 看多 / 上涨 = 品牌青绿（绿 = 正向 = 信号），区域无关全站统一
        bear: "#FF5C6C", // 看空 / 下跌 = 珊瑚红（区域无关全站统一，不随地区红绿翻转）
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
        mono: ["var(--font-mono)", "ui-sans-serif", "sans-serif"],
      },
      // QuiverQuant 圆角尺度：小圆角（卡片 2–4px）+ 胶囊（full）。flatten 掉大圆角的「AI 味」。
      borderRadius: {
        none: "0px",
        sm: "2px",
        DEFAULT: "2px",
        md: "3px",
        lg: "4px",
        xl: "4px",
        "2xl": "6px",
        "3xl": "8px",
        full: "9999px",
      },
    },
  },
  plugins: [],
};

export default config;
