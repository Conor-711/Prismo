"use client";

import { useEffect, useRef, useState } from "react";

export function ViewportWorkspace({
  children,
  className = "",
  bottomOffset = 32,
}: {
  children: React.ReactNode;
  className?: string;
  bottomOffset?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [height, setHeight] = useState<number | null>(null);

  useEffect(() => {
    const html = document.documentElement;
    const body = document.body;
    const appMain = document.querySelector<HTMLElement>(".app-main");
    const prevHtmlOverflow = html.style.overflow;
    const prevBodyOverflow = body.style.overflow;
    const prevHtmlOverscroll = html.style.overscrollBehavior;
    const prevBodyOverscroll = body.style.overscrollBehavior;
    const prevAppMainHeight = appMain?.style.height ?? "";
    const prevAppMainOverflow = appMain?.style.overflow ?? "";

    window.scrollTo(0, 0);
    html.style.overflow = "hidden";
    body.style.overflow = "hidden";
    html.style.overscrollBehavior = "none";
    body.style.overscrollBehavior = "none";
    if (appMain) {
      appMain.style.height = "100vh";
      appMain.style.overflow = "hidden";
    }

    return () => {
      html.style.overflow = prevHtmlOverflow;
      body.style.overflow = prevBodyOverflow;
      html.style.overscrollBehavior = prevHtmlOverscroll;
      body.style.overscrollBehavior = prevBodyOverscroll;
      if (appMain) {
        appMain.style.height = prevAppMainHeight;
        appMain.style.overflow = prevAppMainOverflow;
      }
    };
  }, []);

  useEffect(() => {
    const update = () => {
      const top = ref.current?.getBoundingClientRect().top ?? 0;
      const density = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--app-density")) || 1;
      setHeight(Math.max(360 / density, (window.innerHeight - top - bottomOffset) / density));
    };
    update();
    window.addEventListener("resize", update);
    const observer = new ResizeObserver(update);
    observer.observe(document.body);
    return () => {
      window.removeEventListener("resize", update);
      observer.disconnect();
    };
  }, [bottomOffset]);

  return (
    <div ref={ref} className={className} style={{ height: height ? `${height}px` : "calc(100vh - 116px)" }}>
      {children}
    </div>
  );
}
