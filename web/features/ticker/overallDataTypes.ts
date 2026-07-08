export interface ChartMarker {
  day: string;
  direction?: "up" | "down";
  reason: { zh: string; en: string };
}

export interface VolRow {
  day: string;
  total: number;
  [key: string]: number | string;
}
