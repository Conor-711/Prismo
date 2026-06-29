"use client";

// 标的「值得参考的投资者」简单排行榜：覆盖该标的的博主，按【跨标的验证过的选股技能 z】排名。
// 每行：名次 + 头像 + @handle + 当前立场 + 最近一条观点(一句话) + 技能分 z。
import { useState } from "react";
import type { TopInvestorBoard, InvestorStance } from "@/lib/topInvestors";

const STANCE: Record<InvestorStance, { zh: string; en: string; cls: string }> = {
  bull: { zh: "看多", en: "Bull", cls: "text-bull bg-bull/10 ring-bull/25" },
  bear: { zh: "看空", en: "Bear", cls: "text-bear bg-bear/10 ring-bear/25" },
  neutral: { zh: "中性", en: "Neutral", cls: "text-neutral-400 bg-white/[.05] ring-line" },
};

function Avatar({ src, name }: { src: string; name: string }) {
  const [err, setErr] = useState(false);
  if (err || !src)
    return (
      <div className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-elevated text-[13px] font-semibold text-neutral-400 ring-1 ring-inset ring-line">
        {name.charAt(0).toUpperCase()}
      </div>
    );
  return (
    <img src={src} alt={name} onError={() => setErr(true)}
      className="h-8 w-8 shrink-0 rounded-full bg-elevated object-cover ring-1 ring-inset ring-line" />
  );
}

export function TopInvestors({ board, zh }: { board: TopInvestorBoard; zh: boolean }) {
  return (
    <div>
      <ol className="divide-y divide-line">
        {board.investors.map((inv, i) => {
          const st = STANCE[inv.stance];
          const latest = inv.latest?.[0];
          return (
            <li key={inv.handle} className="flex items-center gap-3 py-2.5">
              <span
                className="w-5 shrink-0 text-center font-mono text-[13px] font-bold tabular"
                style={{ color: i < 3 ? "#57D7BA" : "#6b6d70" }}
              >
                {i + 1}
              </span>
              <Avatar src={inv.avatar} name={inv.name} />
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <a
                    href={`https://x.com/${inv.handle}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="min-w-0 truncate text-[13.5px] font-semibold text-cream transition hover:text-reddit"
                  >
                    @{inv.handle}
                  </a>
                  <span className={`shrink-0 rounded px-1.5 py-0.5 text-[10px] ring-1 ring-inset ${st.cls}`}>{zh ? st.zh : st.en}</span>
                </div>
                {latest && <p className="mt-0.5 truncate text-[11.5px] text-neutral-500">{latest.text}</p>}
              </div>
              <div className="shrink-0 text-right">
                <div className="font-mono text-[14px] font-bold tabular text-[#57D7BA]">z {inv.skillZ.toFixed(1)}</div>
                <div className="text-[10px] text-neutral-600">{zh ? "选股技能" : "skill"}</div>
              </div>
            </li>
          );
        })}
      </ol>
      <p className="mt-3 border-t border-line pt-2.5 text-[10.5px] text-neutral-600">
        {zh
          ? "按博主「跨标的选股技能 z」排名（样本外验证，非单票运气）。参考信号，非投资建议。"
          : "Ranked by cross-ticker stock-picking skill (z, out-of-sample validated). Reference signal, not advice."}
      </p>
    </div>
  );
}
