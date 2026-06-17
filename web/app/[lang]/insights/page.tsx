import { InsightsDashboard } from "@/components/InsightsDashboard";

// 网站数据看板（埋点聚合）。登录后可见；数据来自 Supabase 的 app_events。
export default function InsightsPage() {
  return (
    <div className="max-w-5xl mx-auto py-2">
      <InsightsDashboard />
    </div>
  );
}
