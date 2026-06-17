"use client";

// 轻量埋点 + 聚合读取（Supabase 后端）。未配置 Supabase 时全部静默降级。
// 后端 schema 见 supabase/migrations/20260611000001_analytics.sql。
import { supabase } from "./supabase";

const VKEY = "redditalpha:vid"; // 持久访客 id（localStorage）
const SKEY = "redditalpha:sid"; // 会话 id（sessionStorage）
const DNT = "redditalpha:dnt"; // 「不记录本设备」标记（管理员/自己），排除自有访问
const FKEY = "redditalpha:fseen"; // 首次访问时间戳 ms（localStorage）→ 新/回访判定 + 同期群
const SSTART = "redditalpha:sstart"; // 本会话是否已发过 session_start（sessionStorage）

// 本设备是否已选择「排除我的访问」。开启后 track() 直接静默返回，事件根本不写入。
export function isTrackingDisabled(): boolean {
  try {
    return localStorage.getItem(DNT) === "1";
  } catch {
    return false;
  }
}

// 开/关「排除本设备访问」。登录为管理员时会自动开启（见 AuthProvider），也可手动切换。
export function setTrackingDisabled(off: boolean): void {
  try {
    if (off) localStorage.setItem(DNT, "1");
    else localStorage.removeItem(DNT);
  } catch {
    /* ignore */
  }
}

function uid(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return Math.random().toString(36).slice(2) + Date.now().toString(36);
  }
}

// 只统计「线上」访问：本地 / 内网（localhost、127.x、0.x、192.168.x、10.x、*.local、无点主机名）一律不记录。
function isLocalHost(): boolean {
  try {
    const h = window.location.hostname;
    if (!h || h === "localhost" || h === "::1" || h.endsWith(".local")) return true;
    if (/^(127\.|0\.0\.0\.0|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/.test(h)) return true;
    if (!h.includes(".")) return true; // 无点主机名（容器内部名等）视为非正式访问
    return false;
  } catch {
    return true;
  }
}

function visitorId(): string {
  try {
    let v = localStorage.getItem(VKEY);
    if (!v) {
      v = uid();
      localStorage.setItem(VKEY, v);
    }
    return v;
  } catch {
    return "anon";
  }
}

function sessionId(): string {
  try {
    let s = sessionStorage.getItem(SKEY);
    if (!s) {
      s = uid();
      sessionStorage.setItem(SKEY, s);
    }
    return s;
  } catch {
    return "sess";
  }
}

// 首次访问时间戳（ms）。不存在则创建 → 用于新/回访判定与「距首访天数」。
function firstSeen(): number {
  try {
    let v = localStorage.getItem(FKEY);
    if (!v) {
      v = String(Date.now());
      localStorage.setItem(FKEY, v);
    }
    return Number(v) || Date.now();
  } catch {
    return Date.now();
  }
}

// 当前页 referrer 的 host（拿不到返回 null）。
function refHost(): string | null {
  try {
    return document.referrer ? new URL(document.referrer).host : null;
  } catch {
    return null;
  }
}

// 获取渠道归类（参考 GA4/UTM 口径）：direct / organic / social / paid / email / referral / internal / campaign。
function classifyChannel(host: string | null, utmMedium: string | null, utmSource: string | null): string {
  const m = (utmMedium || "").toLowerCase();
  if (m) {
    if (/cpc|ppc|paid|display|banner|ads?$/.test(m)) return "paid";
    if (/social/.test(m)) return "social";
    if (/email|newsletter|mail/.test(m)) return "email";
    if (/organic|seo/.test(m)) return "organic";
    if (/referr?al/.test(m)) return "referral";
  }
  const h = (host || "").toLowerCase();
  if (!h) return utmSource ? "campaign" : "direct";
  if (/(^|\.)redditalpha\.xyz$/.test(h)) return "internal";
  if (/(google|bing|yahoo|duckduckgo|baidu|yandex|ecosia|sogou|so\.com)\./.test(h)) return "organic";
  if (/(reddit|t\.co|twitter|x\.com|facebook|fb\.com|lnkd\.in|linkedin|youtu|instagram|tiktok|weibo|telegram|t\.me|discord|pinterest|threads)/.test(h)) return "social";
  return "referral";
}

// 设备 / 操作系统 / 浏览器（轻量 UA 解析，仅做画像分桶，非精确）。
function deviceInfo(): { device: string; os: string; browser: string } {
  const ua = (typeof navigator !== "undefined" && navigator.userAgent) || "";
  const touch = (typeof navigator !== "undefined" && navigator.maxTouchPoints) || 0;
  // iPadOS 13+ 的 Safari 默认上报「桌面版」UA（Macintosh），用触点数区分真 Mac 与 iPad。
  const iPadDesktop = /Macintosh/i.test(ua) && touch > 1;
  // 关键：iPhone/iPad 的 UA 也含「like Mac OS X」，故必须先判 iOS，再判 macOS，否则 iPhone 会被误判为 macOS。
  const isIOS = /iPhone|iPad|iPod/i.test(ua) || iPadDesktop;

  let os = "Other";
  if (isIOS) os = "iOS";
  else if (/Macintosh|Mac OS X/i.test(ua)) os = "macOS";
  else if (/Windows/i.test(ua)) os = "Windows";
  else if (/Android/i.test(ua)) os = "Android";
  else if (/CrOS/i.test(ua)) os = "ChromeOS";
  else if (/Linux/i.test(ua)) os = "Linux";

  const tablet = /iPad|Tablet|PlayBook|Silk|Android(?!.*Mobile)/i.test(ua) || iPadDesktop;
  const mobile = /Mobi|iPhone|iPod|Android.*Mobile|Windows Phone|IEMobile/i.test(ua);
  const device = tablet ? "tablet" : mobile ? "mobile" : "desktop";

  // iOS 上 Chrome/Firefox/Edge 是 WebKit 套壳，UA 用 CriOS/FxiOS/EdgiOS 标识。
  let browser = "Other";
  if (/Edg\/|EdgiOS/i.test(ua)) browser = "Edge";
  else if (/OPR\/|OPiOS|Opera/i.test(ua)) browser = "Opera";
  else if (/CriOS/i.test(ua)) browser = "Chrome";
  else if (/FxiOS/i.test(ua)) browser = "Firefox";
  else if (/Firefox\//i.test(ua)) browser = "Firefox";
  else if (/Chrome\//i.test(ua) && !/Edg\//i.test(ua)) browser = "Chrome";
  else if (/Safari\//i.test(ua) && !/Chrome/i.test(ua)) browser = "Safari";
  return { device, os, browser };
}

// 是否「独立窗口」运行（= 用户把站点加到主屏/安装为 App 后启动）。
// 这是「有多少用户把网站存下来」最接近、且真正可追踪的信号；浏览器原生收藏无法被网页探测。
function isStandalone(): boolean {
  try {
    return (
      (typeof matchMedia !== "undefined" && matchMedia("(display-mode: standalone)").matches) ||
      // iOS Safari 专有：从主屏启动时为 true
      (navigator as unknown as { standalone?: boolean }).standalone === true
    );
  } catch {
    return false;
  }
}

// 底层写入（fire-and-forget）。track 与 ensureSessionStart 共用。
function insertEvent(eventType: string, props: TrackProps): void {
  const row = {
    event_type: eventType,
    path: props.path ?? window.location.pathname,
    lang: props.lang ?? null,
    ticker: props.ticker ?? null,
    ref: refHost(),
    visitor: visitorId(),
    session: sessionId(),
    meta: props.meta ?? null,
  };
  void (async () => {
    try {
      await supabase!.from("app_events").insert(row);
    } catch {
      /* 网络/未配置 → 忽略 */
    }
  })();
}

// 每个会话发一次 session_start，携带「用户画像属性」（设备/渠道/UTM/语言/时区/新老）。
// 受众画像 / 获取渠道 / 留存 等聚合都基于这批 session_start 行。
function ensureSessionStart(): void {
  try {
    if (sessionStorage.getItem(SSTART) === "1") return;
    sessionStorage.setItem(SSTART, "1");
  } catch {
    return; // 无 sessionStorage（隐私模式等）→ 跳过画像，不影响基础埋点
  }
  try {
    const sp = new URLSearchParams(window.location.search);
    const host = refHost();
    const utmSource = sp.get("utm_source");
    const utmMedium = sp.get("utm_medium");
    const utmCampaign = sp.get("utm_campaign");
    const dsf = Math.max(0, Math.floor((Date.now() - firstSeen()) / 86_400_000));
    const { device, os, browser } = deviceInfo();
    let tz = "";
    try {
      tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
    } catch {
      /* ignore */
    }
    insertEvent("session_start", {
      meta: {
        device,
        os,
        browser,
        vw: window.innerWidth,
        sw: typeof screen !== "undefined" ? screen.width : null,
        lang: (navigator.language || "").slice(0, 5),
        tz,
        channel: classifyChannel(host, utmMedium, utmSource),
        utm_source: utmSource,
        utm_medium: utmMedium,
        utm_campaign: utmCampaign,
        landing: window.location.pathname,
        returning: dsf > 0, // 首访之后的不同自然日再来 = 回访
        dsf,
        standalone: isStandalone(), // 从主屏/已安装 App 启动 = 把站点「存下来」的用户
      },
    });
  } catch {
    /* 画像采集失败不应影响其它埋点 */
  }
}

export interface TrackProps {
  path?: string;
  lang?: string;
  ticker?: string;
  meta?: Record<string, unknown>;
}

// 记录一次行为事件（fire-and-forget；不阻塞、不报错冒泡）。
// 每个会话首个事件前会自动补发一次 session_start（用户画像）。
export function track(eventType: string, props: TrackProps = {}): void {
  if (!supabase || typeof window === "undefined") return;
  if (isLocalHost()) return; // 只统计线上访问，忽略本地/内网
  if (isTrackingDisabled()) return; // 本设备已选择「排除我的访问」→ 不记录
  if (eventType !== "session_start") ensureSessionStart();
  insertEvent(eventType, props);
}

// 调用聚合函数；未配置 / 出错 / 未授权 → null。
export async function analyticsRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T | null> {
  if (!supabase) return null;
  try {
    const { data, error } = await supabase.rpc(fn, args);
    if (error) return null;
    return (data ?? null) as T | null;
  } catch {
    return null;
  }
}
