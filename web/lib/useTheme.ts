// 站点为暗色单主题（已停用白天模式）。此 hook 仅为兼容现有图表(ECharts)调用：
// 恒为「非白天」，让 canvas 图表始终取暗色配色；不再依赖 <html> 的 .dark 类。
export function useIsLight(): boolean {
  return false;
}
