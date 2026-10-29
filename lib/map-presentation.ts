export const mapPageSize = 3;
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

/** Static SVG only: no personal text is placed permanently on the map. */
export function markerIconSvg(role:string,platform:string){
 const paths=/origem|origin/i.test(role)?'<circle cx="12" cy="12" r="6"/>':/restaurante|loja|shop|restaurant/i.test(role)?'<path d="M3 10h18M5 10v11h14V10M3 10l2-7h14l2 7M9 21v-7h6v7"/>':/destino|destination/i.test(role)?'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2"/>':/cliente|passageiro|rider|customer/i.test(role)?'<circle cx="12" cy="7" r="4"/><path d="M4 21v-3a8 8 0 0 1 16 0v3"/>':/market|taomoz/i.test(platform)?'<path d="M2 3h3l3 12h11l3-9H6"/><circle cx="9" cy="20" r="1"/><circle cx="19" cy="20" r="1"/>':/sarca/i.test(platform)?'<path d="m4 9 2-6h12l2 6M3 10h18v8H3zM5 18v3M19 18v3M6 13h2M16 13h2"/>':'<circle cx="5" cy="18" r="3"/><circle cx="19" cy="18" r="3"/><path d="M5 18h9l3-10h-5M15 4h4l2 10M4 11h6l3 7"/>';
 return `<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
}
export function cleanMapMarkers<T extends {id:string;workerId?:string;role:string;platform:string;locationKind?:string;updatedAt?:string}>(markers:T[],selectedRouteId?:string,showAllEntities=false){
 const seen=new Set<string>();
 return [...markers].sort((a,b)=>(Date.parse(b.updatedAt||"")||0)-(Date.parse(a.updatedAt||"")||0)).filter(marker=>{
  const selectedEndpoint=Boolean(selectedRouteId&&marker.locationKind==="endpoint"&&marker.id.startsWith(selectedRouteId+":"));
  if(!showAllEntities&&!selectedEndpoint&&(marker.locationKind==="endpoint"||marker.locationKind==="place"||/cliente|customer|rider|passageiro|restaurante|loja/i.test(marker.role)))return false;
  const key=marker.workerId&&(!marker.locationKind||marker.locationKind==="gps")?`${marker.platform}:${marker.workerId}`:marker.id;
  if(seen.has(key))return false;seen.add(key);return true;
 });
}
