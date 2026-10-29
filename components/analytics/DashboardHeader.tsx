import type { ReactNode } from "react";

export function DashboardHeader({ actions }: { title: string; description?: string; actions?: ReactNode; updatedAt?: string }) {
  if (!actions) return null;
  return <header className="analyticsDashboardHeader"><div className="analyticsHeaderActions">{actions}</div></header>;
}
