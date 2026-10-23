export type AnalyticsUnit = "MZN" | "%" | "count" | "seconds" | "minutes";
export type AnalyticsPeriod = "today" | "last_7_days" | "last_30_days" | "last_90_days" | "this_year" | "custom";
export type AnalyticsSourceStatus = "fresh" | "stale" | "unavailable";
export type AnalyticsPermission = string;

export type AnalyticsFilters = {
  period: AnalyticsPeriod;
  from?: string;
  to?: string;
  platform?: string;
  department?: string;
  priority?: string;
  agent?: string;
  location?: string;
  status?: string;
  timezone: "Africa/Maputo";
};

export type KPIResult = {
  id: string;
  label: string;
  value: number | null;
  unit: AnalyticsUnit;
  previousValue?: number | null;
  changePercent?: number | null;
  periodStart?: string;
  periodEnd?: string;
  updatedAt?: string;
  sourceStatus: AnalyticsSourceStatus;
  source?: string;
  permission?: AnalyticsPermission;
};

export type AnalyticsError = {
  code: "unauthorized" | "unavailable" | "invalid_filters" | "unknown";
  message: string;
  retryable: boolean;
};

export type AnalyticsDataState<T> = {
  data: T | null;
  loading: boolean;
  error: AnalyticsError | null;
  updatedAt?: string;
};

export type ChartSeries = {
  id: string;
  label: string;
  unit?: AnalyticsUnit;
  values: Array<{ label: string; value: number | null }>;
};

export type ExportFormat = "csv" | "xlsx" | "pdf";

export const defaultAnalyticsFilters: AnalyticsFilters = {
  period: "last_30_days",
  timezone: "Africa/Maputo",
};

export function percentChange(value: number, previous: number): number | null {
  if (previous === 0) return null;
  return ((value - previous) / previous) * 100;
}
