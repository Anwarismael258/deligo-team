export function EmptyState({ title = "Sem dados disponíveis", description = "A fonte autorizada ainda não devolveu registos para este contexto." }: { title?: string; description?: string }) {
  return <div className="analyticsEmptyState"><strong>{title}</strong><span>{description}</span></div>;
}
