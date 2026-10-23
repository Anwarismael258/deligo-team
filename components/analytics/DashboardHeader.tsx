import type { ReactNode } from "react";

export function DashboardHeader({ title, description, actions, updatedAt }: { title: string; description?: string; actions?: ReactNode; updatedAt?: string }) {
  return <header className="analyticsDashboardHeader"><div><span className="analyticsEyebrow">CENTRAL HQ · ANALYTICS</span><h2>{title}</h2>{description && <p>{description}</p>}</div><div className="analyticsHeaderActions">{updatedAt && <small>Actualizado {updatedAt}</small>}{actions}</div></header>;
}
