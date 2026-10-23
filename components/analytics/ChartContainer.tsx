import type { ReactNode } from "react";

export function ChartContainer({ title, description, children }: { title: string; description?: string; children: ReactNode }) {
  return <section className="analyticsChartContainer"><div className="analyticsChartHeading"><div><h3>{title}</h3>{description && <p>{description}</p>}</div></div>{children}</section>;
}
