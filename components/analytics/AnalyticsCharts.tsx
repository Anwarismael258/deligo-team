"use client";

import { Bar, BarChart, CartesianGrid, Cell, Line, LineChart, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { EmptyState } from "./EmptyState";

export type AnalyticsChartItem = { label: string; value: number };
export type AnalyticsSeriesItem = { date: string; value: number; secondary?: number };

const red = "#9f1d35";
const orange = "#e47725";
const palette = [red, orange, "#d7a33d", "#6f7b93", "#4e9b79", "#8d5aa7"];
const formatNumber = (value: number) => value.toLocaleString("pt-MZ", { maximumFractionDigits: 2 });
const hasValues = (items: Array<{ value: number }> | undefined) => Boolean(items?.some(item => Number.isFinite(item.value)));

function unavailable(title: string) {
  return <EmptyState title={title} description="A fonte autorizada não devolveu dados suficientes para desenhar este gráfico." />;
}

export function AnalyticsLineChart({ data, label = "Valor", secondaryLabel }: { data?: AnalyticsSeriesItem[]; label?: string; secondaryLabel?: string }) {
  if (!hasValues(data)) return unavailable("Série histórica indisponível");
  return <div className="analyticsChartCanvas" aria-label={label} style={{ width: "100%", height: 240, minWidth: 0 }}>
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={240}>
      <LineChart data={data} margin={{ top: 8, right: 12, left: 0, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#eadfda" />
        <XAxis dataKey="date" tick={{ fontSize: 10 }} tickLine={false} axisLine={false} />
        <YAxis tick={{ fontSize: 10 }} tickLine={false} axisLine={false} width={56} />
        <Tooltip formatter={(value: unknown, name: unknown) => [typeof value === "number" ? formatNumber(value) : "Indisponível", String(name)]} />
        <Line type="monotone" dataKey="value" name={label} stroke={red} strokeWidth={3} dot={{ r: 2 }} activeDot={{ r: 5 }} />
        {secondaryLabel && <Line type="monotone" dataKey="secondary" name={secondaryLabel} stroke={orange} strokeWidth={2} dot={{ r: 2 }} />}
      </LineChart>
    </ResponsiveContainer>
  </div>;
}

export function AnalyticsBarChart({ data, label = "Total" }: { data?: AnalyticsChartItem[]; label?: string }) {
  if (!hasValues(data)) return unavailable("Distribuição indisponível");
  const items = data || [];
  return <div className="analyticsChartCanvas" aria-label={label} style={{ width: "100%", height: 240, minWidth: 0 }}>
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={240}>
      <BarChart data={items} margin={{ top: 8, right: 12, left: 0, bottom: 4 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#eadfda" />
        <XAxis dataKey="label" tick={{ fontSize: 10 }} tickLine={false} axisLine={false} interval={0} angle={items.length > 5 ? -25 : 0} textAnchor={items.length > 5 ? "end" : "middle"} height={items.length > 5 ? 58 : 30} />
        <YAxis tick={{ fontSize: 10 }} tickLine={false} axisLine={false} width={40} />
        <Tooltip formatter={(value: unknown) => [typeof value === "number" ? formatNumber(value) : "Indisponível", label]} />
        <Bar dataKey="value" name={label} fill={red} radius={[5, 5, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  </div>;
}

export function AnalyticsDonutChart({ data }: { data?: AnalyticsChartItem[] }) {
  if (!hasValues(data)) return unavailable("Distribuição indisponível");
  const items = data || [];
  return <div className="analyticsChartCanvas" aria-label="Distribuição" style={{ width: "100%", height: 240, minWidth: 0 }}>
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={240}>
      <PieChart>
        <Pie data={items} dataKey="value" nameKey="label" innerRadius="52%" outerRadius="78%" paddingAngle={2}>
          {items.map((item, index) => <Cell key={`${item.label}-${index}`} fill={palette[index % palette.length]} />)}
        </Pie>
        <Tooltip formatter={(value: unknown) => [typeof value === "number" ? formatNumber(value) : "Indisponível", "Total"]} />
      </PieChart>
    </ResponsiveContainer>
  </div>;
}
