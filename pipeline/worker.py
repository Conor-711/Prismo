"""调度器：每天 UTC+8 08:00 跑一次全量流程，分析「过去 24 小时」的 Reddit 信息。

不再实时爬取——以 UTC+8 时区的 24 小时为界线，每天清晨分析一次即可。
跑完会顺带重建静态站点（web/out），让部署页面反映最新一天的数据。
"""
from __future__ import annotations

from apscheduler.schedulers.blocking import BlockingScheduler

from .common.config import settings
from .common.db import init_db
from .daily import run_daily

TIMEZONE = "Asia/Shanghai"  # UTC+8
HOUR, MINUTE = 8, 0


def _daily():
    try:
        run_daily(rebuild=True)
    except Exception as e:  # noqa: BLE001
        print(f"[worker] daily 失败：{e}")


def main():
    init_db()
    if not settings.has_reddit:
        print("[worker] ℹ️ 无 Reddit 凭证：使用 Arctic Shift 镜像爬取真实数据。")
    if not settings.has_anthropic:
        print("[worker] ⚠️ 缺 ANTHROPIC_API_KEY，AI 打标/叙事/简报将使用 mock。")

    sched = BlockingScheduler(timezone=TIMEZONE)
    sched.add_job(_daily, "cron", hour=HOUR, minute=MINUTE, id="daily")
    print(f"[worker] 调度启动：每天 {HOUR:02d}:{MINUTE:02d} {TIMEZONE}（UTC+8）分析过去 24 小时并重建站点。")
    print("[worker] 立即跑一次以初始化（之后按日程运行）。Ctrl+C 退出。")
    _daily()
    try:
        sched.start()
    except (KeyboardInterrupt, SystemExit):
        print("[worker] 已停止。")


if __name__ == "__main__":
    main()
