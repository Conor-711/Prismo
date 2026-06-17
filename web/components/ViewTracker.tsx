"use client";

import { useEffect, useRef } from "react";
import { track } from "@/lib/analytics";

// MRC 可见曝光口径：元素 ≥50% 进入视口、保持连续 ≥1 秒、且页面在前台 → 记一次 ad_view。
// 每次挂载只记一次（一次页面浏览=一次该广告位的可见曝光机会）。包裹真实内容/广告位，零视觉改动。
export function ViewTracker({
  slot,
  children,
  className,
}: {
  slot: string;
  children?: React.ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const fired = useRef(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    let timer: number | null = null;
    const clear = () => {
      if (timer) {
        window.clearTimeout(timer);
        timer = null;
      }
    };
    const io = new IntersectionObserver(
      (entries) => {
        const e = entries[0];
        const visible = e.isIntersecting && e.intersectionRatio >= 0.5 && document.visibilityState === "visible";
        if (visible && !fired.current && !timer) {
          timer = window.setTimeout(() => {
            timer = null;
            if (!fired.current && document.visibilityState === "visible") {
              fired.current = true;
              track("ad_view", { meta: { slot } });
              io.disconnect();
            }
          }, 1000); // 连续 1 秒
        } else if (!visible) {
          clear(); // 离开视口/切后台 → 计时作废，下次重新计
        }
      },
      { threshold: [0, 0.5, 1] }
    );
    io.observe(el);
    const onVis = () => {
      if (document.visibilityState === "hidden") clear();
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      clear();
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [slot]);

  return (
    <div ref={ref} className={className} data-ad-slot={slot}>
      {children}
    </div>
  );
}
