export function TrendIndicator({ changePercent }: { changePercent: number | null | undefined }) {
  if (changePercent == null) return <span className="analyticsTrendNeutral">Sem base comparável</span>;
  return <span className={changePercent >= 0 ? "analyticsTrendPositive" : "analyticsTrendNegative"}>{changePercent >= 0 ? "↑" : "↓"} {Math.abs(changePercent).toFixed(1)}%</span>;
}
