import type { ReactNode } from "react";

export type AnalyticsColumn<Row> = { key: string; label: string; render?: (row: Row) => ReactNode };

export function AnalyticsDataTable<Row extends Record<string, unknown>>({ rows, columns, empty = "Sem registos" }: { rows: Row[]; columns: AnalyticsColumn<Row>[]; empty?: string }) {
  if (!rows.length) return <div className="analyticsEmptyState">{empty}</div>;
  return <div className="analyticsTableWrap"><table className="analyticsDataTable"><thead><tr>{columns.map((column) => <th key={column.key}>{column.label}</th>)}</tr></thead><tbody>{rows.map((row, index) => <tr key={String(row.id || index)}>{columns.map((column) => <td key={column.key}>{column.render ? column.render(row) : String(row[column.key] ?? "—")}</td>)}</tr>)}</tbody></table></div>;
}
