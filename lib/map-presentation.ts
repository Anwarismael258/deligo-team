export const mapPageSize = 6;
export function mapColor(platform: string) {
  return /sarca/i.test(platform) ? "#a78bfa" : /market|taomoz/i.test(platform) ? "#fb923c" : "#22d3ee";
}
export function markerName(marker: { workerName?: string; service?: string; role?: string }) {
  return marker.workerName?.trim() || marker.service?.trim() || marker.role || "Localização";
}
export function markerGlyph(role: string, platform: string) {
  if (/restaurante|loja|shop|restaurant/i.test(role)) return "▣";
  if (/cliente|passageiro|rider|customer/i.test(role)) return "♙";
  if (/destino|destination/i.test(role)) return "⚑";
  if (/recolha|pedido|viagem|encomenda/i.test(role)) return "⌖";
  return /sarca/i.test(platform) ? "🚗" : /market|taomoz/i.test(platform) ? "🛒" : "🏍";
}
export function escapeMapText(value: string) {
  return value.replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]!));
}
export function pageOperations<T>(items: T[], requestedPage: number) {
  const pages = Math.max(1, Math.ceil(items.length / mapPageSize));
  const page = Math.max(0, Math.min(requestedPage, pages - 1));
  return { page, pages, items: items.slice(page * mapPageSize, (page + 1) * mapPageSize) };
}

export function clusterMapMarkers<T>(markers: T[], project: (marker: T) => { x: number; y: number }, cellSize = 64): T[][] {
  const cells = new Map<string, T[]>();
  for (const marker of markers) {
    const point = project(marker);
    const key = `${Math.floor(point.x / cellSize)}:${Math.floor(point.y / cellSize)}`;
    const cell = cells.get(key) || [];
    cell.push(marker);cells.set(key, cell);
  }
  return [...cells.values()];
}
