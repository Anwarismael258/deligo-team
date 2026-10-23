import type { ReactNode } from "react";

export function DashboardShell({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <section className={`analyticsDashboardShell ${className}`.trim()}>{children}</section>;
}
