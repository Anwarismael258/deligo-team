export function DataFreshnessIndicator({ status, updatedAt }: { status: "fresh" | "stale" | "unavailable"; updatedAt?: string }) {
  if (status === "unavailable") return null;
  const label = status === "fresh" ? "Fonte actualizada" : status === "stale" ? "Fonte desactualizada" : "Fonte indisponível";
  return <span className={`analyticsFreshness analyticsFreshness-${status}`}><i aria-hidden="true" />{label}{updatedAt ? ` · ${updatedAt}` : ""}</span>;
}
