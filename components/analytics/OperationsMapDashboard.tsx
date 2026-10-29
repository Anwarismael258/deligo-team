"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import LiveOperationsMap, { type OperationsMapMarker, type OperationsMapRoute } from "@/components/LiveOperationsMap";
import { DashboardFilters } from "./DashboardFilters";
import { OperationsDensityHeatmap } from "./OperationsDensityHeatmap";
import { cleanMapMarkers, mapColor, markerIconSvg, markerName, pageOperations, mapPageSize } from "@/lib/map-presentation";
import styles from "./OperationsMapDashboard.module.css";
import type { AnalyticsFilters } from "@/lib/analytics-contracts";

type MapPayload = { checkedAt?: string; markers?: OperationsMapMarker[]; routes?: OperationsMapRoute[]; sourceStatus?: "fresh" | "unavailable"; sourceMessage?: string };
type HistoryPayload = { series: Array<{ date: string; events: number; deliveriesCompleted: number; ridesCompleted: number; cancellations: number }>; totals?: { deliveriesCompleted?: number; ridesCompleted?: number } };
type Selection = { kind: "marker" | "route"; id: string };
const platforms = ["Todas as plataformas", "DeliGo", "SARCA", "DeliGo Market"];
const entities = ["Todas as entidades", "Pedidos", "Viagens", "Rotas", "Estafetas", "Drivers", "Riders", "Clientes", "Restaurantes"];
const statuses = ["Todos os estados", "Disponível", "Ocupado", "Em serviço", "Offline"];
const gpsStatusLabel = "GPS desactualizado";
const platformDistributionLabel = "Distribuição por plataforma";
const normalize = (value: string) => value.toLocaleLowerCase("pt-MZ").normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const platformName = (value: string) => value === "TaoMoz" ? "DeliGo Market" : value === "DeliGo Eats" ? "DeliGo" : value;
const statusName = (value?: string) => ({ disponivel: "Disponível", ocupado: "Ocupado", em_servico: "Em serviço", offline: "Offline", searching_driver: "A procurar motorista", driver_assigned: "Motorista atribuído", driver_arriving: "Motorista a chegar", in_progress: "Em viagem", preparing: "Em preparação", ready_for_pickup: "Pronto para recolha", on_the_way: "Em entrega" }[value || ""] || value || "Não indicado");
const entityMatches = (marker: OperationsMapMarker, entity: string) => { if (entity === entities[0]) return true; const aliases: Record<string, string[]> = { Pedidos: ["pedido", "order", "delivery", "entrega"], Viagens: ["viagem", "trip", "ride"], Rotas: ["rota", "route"], Estafetas: ["estafeta", "courier", "entregador"], Drivers: ["driver", "motorista"], Riders: ["rider", "passageiro"], Clientes: ["cliente", "customer", "client"], Restaurantes: ["restaurante", "restaurant"] }; return (aliases[entity] || []).some(alias => normalize((marker.role || "") + " " + (marker.service || "")).includes(alias)); };

export function OperationsMapDashboard() {
  const room = useRef<HTMLDivElement | null>(null);
  const loading = useRef(false);
  const activeRequest = useRef<AbortController | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const [page, setPage] = useState(0);
  const [following, setFollowing] = useState(false);
  const [recenterKey, setRecenterKey] = useState(0);
  const toggleFullscreen = async () => {
    if (fullscreen) { if (document.fullscreenElement === room.current) await document.exitFullscreen(); setFullscreen(false); return; }
    setFullscreen(true);
    try { await room.current?.requestFullscreen?.(); } catch { /* The viewport layout also works where native fullscreen is unavailable. */ }
  };
  useEffect(() => {
    const changed = () => { if (!document.fullscreenElement) setFullscreen(false); };
    const escape = (event: KeyboardEvent) => { if (event.key === "Escape") setFullscreen(false); };
    document.addEventListener("fullscreenchange", changed); document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("fullscreenchange", changed); document.removeEventListener("keydown", escape); };
  }, []);
  useEffect(() => { if (!fullscreen) return; const previous = document.body.style.overflow; document.body.style.overflow = "hidden"; return () => { document.body.style.overflow = previous; }; }, [fullscreen]);
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<MapPayload | null>(null); const [history, setHistory] = useState<HistoryPayload | null>(null); const [error, setError] = useState("");
  const [platform, setPlatform] = useState(platforms[0]); const [entity, setEntity] = useState(entities[0]); const [status, setStatus] = useState(statuses[0]); const [search, setSearch] = useState("");
  const [view, setView] = useState<"live" | "history">("live"); const [densityOpen, setDensityOpen] = useState(false); const [selected, setSelected] = useState<Selection | null>(null);
  const load = useCallback(async () => {
    if (loading.current || document.visibilityState === "hidden") return;
    loading.current = true;
    const controller = new AbortController(); activeRequest.current = controller;
    const timeout = window.setTimeout(() => { controller.abort();setError("A ligação está lenta. A tentar novamente…"); }, 15000);
    try {
      const response = await fetch("/api/map", { cache: "no-store", signal: controller.signal });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "A fonte operacional não respondeu.");
      if (!controller.signal.aborted) { setPayload(body);setError(""); }
    } catch (reason) {
      if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : "A ligação foi interrompida.");
    } finally { window.clearTimeout(timeout);loading.current = false; }
  }, []);
  useEffect(() => {
    let disposed = false;let timer: ReturnType<typeof setTimeout>;
    const tick = async () => { await load();if (!disposed) timer = setTimeout(() => void tick(), 3000); };
    const resume = () => { if (document.visibilityState !== "hidden") void load(); };
    void tick();document.addEventListener("visibilitychange", resume);window.addEventListener("focus", resume);
    return () => { disposed = true;clearTimeout(timer);activeRequest.current?.abort();document.removeEventListener("visibilitychange", resume);window.removeEventListener("focus", resume); };
  }, [load]);
  useEffect(() => {
    if (view !== "history") return;
    const controller = new AbortController();
    const params = new URLSearchParams({ period: filters.period });if (filters.from) params.set("from", filters.from);if (filters.to) params.set("to", filters.to);
    void fetch("/api/analytics/map?" + params, { cache: "no-store", signal: controller.signal }).then(async response => { if (!response.ok) throw new Error();return response.json(); }).then(body => { if (!controller.signal.aborted) setHistory(body); }).catch(() => { if (!controller.signal.aborted) setHistory(null); });
    return () => controller.abort();
  }, [view, filters.from, filters.period, filters.to]);
  const markers = Array.isArray(payload?.markers) ? payload.markers : []; const routes = Array.isArray(payload?.routes) ? payload.routes : [];
  const visibleMarkers = useMemo(() => markers.filter(marker => { const okPlatform = platform === platforms[0] || platformName(marker.platform) === platform; const okStatus = status === statuses[0] || statusName(marker.status) === status; const text = normalize([marker.workerName, marker.workerId, marker.role, marker.service, platformName(marker.platform)].filter(Boolean).join(" ")); return okPlatform && okStatus && entityMatches(marker, entity) && text.includes(normalize(search)); }), [entity, markers, platform, search, status]);
  const filteredRoutes = useMemo(() => routes.filter(route => (platform === platforms[0] || platformName(route.platform) === platform) && (entity === entities[0] || ["Pedidos", "Viagens", "Rotas"].includes(entity)) && (status === statuses[0] || status === "Em serviço" || statusName(route.operationStatus) === status) && normalize(route.label + " " + route.platform + " " + (route.workerName || "") + " " + (route.origin || "") + " " + (route.destination || "")).includes(normalize(search))), [entity, platform, routes, search, status]);
  const visibleRoutes = filteredRoutes;
  const recentUnique = useMemo(() => { const seen = new Set<string>(); return visibleMarkers.filter(marker => { if (marker.locationKind && marker.locationKind !== "gps") return false;const time = Date.parse(marker.updatedAt); if (!Number.isFinite(time) || Date.now() - time > 600000) return false; const key = marker.workerId || marker.service || marker.id; if (seen.has(key)) return false; seen.add(key); return true; }); }, [visibleMarkers]);
  const unavailable = payload?.sourceStatus === "unavailable" && markers.length === 0; const selectedMarker = selected?.kind === "marker" ? visibleMarkers.find(marker => marker.id === selected.id) : undefined; const selectedRoute = selected?.kind === "route" ? filteredRoutes.find(route => route.id === selected.id) : selectedMarker ? filteredRoutes.find(route=>selectedMarker.id.startsWith(route.id+":")) : undefined;
  const mapMarkers=useMemo(()=>cleanMapMarkers(visibleMarkers,selectedRoute?.id,entity!==entities[0]),[visibleMarkers,selectedRoute?.id,entity]);
  const listItems = useMemo(() => [
    ...filteredRoutes.map(route => { const driver = visibleMarkers.find(marker => marker.id.startsWith(route.id + ":") && /driver|motorista|estafeta|entregador/i.test(marker.role));return { id: route.id, kind: "route" as const, title: route.label, subtitle: platformName(route.platform), state: statusName(route.operationStatus || "em_servico"), glyph: markerIconSvg("motorista", route.platform), color: mapColor(route.platform) }; }),
    ...visibleMarkers.filter(marker => !/cliente|restaurante|loja/i.test(marker.role) && ["em_servico", "ocupado"].includes(marker.status || "") && !filteredRoutes.some(route => marker.id.startsWith(route.id + ":"))).map(marker => ({ id: marker.id, kind: "marker" as const, title: marker.service || marker.role, subtitle: platformName(marker.platform), state: statusName(marker.status), glyph: markerIconSvg(marker.role, marker.platform), color: mapColor(marker.platform) })),
  ], [visibleMarkers, filteredRoutes]);
  const initialSelection=useRef(false);
  useEffect(()=>{if(!initialSelection.current&&listItems.length){initialSelection.current=true;setSelected({kind:listItems[0].kind,id:listItems[0].id})}},[listItems]);
  const pagination = pageOperations(listItems, page);
  const selectOnMap = useCallback((value: Selection) => { setSelected(value);setFollowing(false);const index = listItems.findIndex(item => item.id === value.id || value.id.startsWith(item.id + ":"));if (index >= 0) setPage(Math.floor(index / mapPageSize)); }, [listItems]);
  const routeDriver = selectedRoute ? markers.find(marker => marker.id.startsWith(selectedRoute.id + ":") && /driver|motorista|estafeta|entregador/i.test(marker.role)) : undefined;
  const followedMarker = selectedMarker || routeDriver;
  const canFollow = Boolean(followedMarker && (!followedMarker.locationKind || followedMarker.locationKind === "gps"));
  const kpis = [["Entregas activas",filteredRoutes.filter(route=>["DeliGo","DeliGo Market"].includes(platformName(route.platform))).length,"cyan"],["Viagens em curso",filteredRoutes.filter(route=>platformName(route.platform)==="SARCA").length,"violet"],["Disponíveis",mapMarkers.filter(marker=>marker.status==="disponivel").length,"green"],["Sem sinal recente",mapMarkers.filter(marker=>(!marker.locationKind||marker.locationKind==="gps")&&(!Number.isFinite(Date.parse(marker.updatedAt))||Date.now()-Date.parse(marker.updatedAt)>600000)).length,"orange"]];
  const detail = (selectedMarker || selectedRoute) ? <div className="operationDetail"><div className="operationDetailHead"><div><span>SELECIONADO</span><strong>{selectedMarker ? markerName(selectedMarker) : selectedRoute?.label}</strong></div><button aria-label="Fechar detalhes" onClick={() => { setSelected(null);setFollowing(false); }}>×</button></div><p>{selectedRoute ? platformName(selectedRoute.platform) : selectedMarker?.role + " · " + platformName(selectedMarker?.platform || "")}</p><dl>
    <dt>Responsável</dt><dd>{followedMarker?.workerName || selectedRoute?.workerName || "Sem responsável identificado"}</dd>
    <dt>Estado</dt><dd>{selectedMarker ? statusName(selectedMarker.status) : statusName(selectedRoute?.operationStatus || "em_servico")}</dd>
    {(selectedMarker?.origin || selectedRoute?.origin) && <><dt>Origem</dt><dd>{selectedMarker?.origin || selectedRoute?.origin}</dd></>}
    {(selectedMarker?.destination || selectedRoute?.destination) && <><dt>Destino</dt><dd>{selectedMarker?.destination || selectedRoute?.destination}</dd></>}
    {followedMarker && <><dt>{followedMarker.locationKind === "endpoint" ? "Ponto registado" : "Última posição"}</dt><dd>{new Date(followedMarker.updatedAt).toLocaleTimeString("pt-MZ")}{(!followedMarker.locationKind || followedMarker.locationKind === "gps") && Date.now() - Date.parse(followedMarker.updatedAt) > 60000 ? " · " + gpsStatusLabel : ""}</dd></>}
    {selectedRoute && <><dt>Pontos</dt><dd>{selectedRoute.coordinates.length === 2 ? "Origem e destino" : `${selectedRoute.coordinates.length} posições registadas`}</dd></>}
    </dl><button className="operationFollow" disabled={!canFollow} onClick={() => setFollowing(value => !value)}>{following ? "Parar acompanhamento" : "Acompanhar no mapa"}</button></div> : null;
  return <section className={`operationsControlRoom ${styles.room}`}><header className="operationsRoomHeader"><div className="operationsRoomHeaderActions"><small>{payload?.checkedAt ? "Actualizado " + new Date(payload.checkedAt).toLocaleTimeString("pt-MZ") : "A preparar leitura"}</small><span className="operationsViewTabs"><button className={view === "live" ? "active" : ""} onClick={() => setView("live")}>Ao vivo</button><button className={view === "history" ? "active" : ""} onClick={() => setView("history")}>Histórico</button></span><button onClick={() => void load()}>↻ Actualizar</button></div></header>
    <div className="operationsRoomFilters"><input aria-label="Pesquisar pedido, viagem ou pessoa" value={search} onChange={event => { setSearch(event.target.value);setPage(0); }} placeholder="⌕  Pesquisar pedido, viagem ou pessoa…" /><label>Estado<select value={status} onChange={event => { setStatus(event.target.value);setPage(0); }}>{statuses.map(item => <option key={item}>{item}</option>)}</select></label><label>Entidade<select value={entity} onChange={event => { setEntity(event.target.value);setPage(0); }}>{entities.map(item => <option key={item}>{item}</option>)}</select></label></div>{view === "history" && <DashboardFilters value={filters} onChange={setFilters} platforms={[]} />}<div className="operationsPlatformTabs" aria-label="Plataforma">{platforms.map(item => <button key={item} className={platform === item ? "active" : ""} onClick={() => { setPlatform(item);setPage(0);setSelected(null);setFollowing(false); }}>{item === platforms[0]?"Todas":item === "DeliGo" ? "DeliGo Eats" : item}</button>)}</div>{error && <div className="operationsRoomNotice error">{error}</div>}
    {view === "history" && <div className="operationsKpis">{kpis.map(([label, value, color]) => <article className={String(color)} key={String(label)}><span>{label}</span><strong>{error || unavailable ? "—" : value}</strong></article>)}</div>}
    {view === "live" ? <><div className="operationsRoomGrid"><div className={styles.mapColumn}><div className="operationsKpis">{kpis.map(([label, value, color]) => <article className={String(color)} key={String(label)}><span>{label}</span><strong>{error || unavailable ? "—" : value}</strong></article>)}</div><div ref={room} className={`operationsMapStage ${fullscreen ? styles.mapFullscreen : ""}`}><div className="operationsMapStageHead"><div><strong>Operações no mapa</strong><small>{mapMarkers.length} posições · seleccione um ícone para ver detalhes</small></div><div className="operationsMapControls"><button onClick={() => void toggleFullscreen()}>{fullscreen ? "Sair da tela cheia" : "Tela cheia"}</button><button onClick={() => { setFollowing(false);setRecenterKey(value => value + 1); }}>Recentrar</button><span>{unavailable ? "Fonte GPS indisponível" : "Dados autorizados"}</span></div></div>{payload ? <LiveOperationsMap markers={mapMarkers} routes={selectedRoute ? [selectedRoute] : []} onSelect={selectOnMap} selected={selected} following={following} followId={followedMarker?.id} recenterKey={recenterKey} /> : <div className="operationsMapEmpty">A preparar o mapa…</div>}{densityOpen && <div className="operationsDensityPanel"><strong>Densidade de posições recentes</strong><small>Uma posição por entidade · últimos 10 minutos</small><OperationsDensityHeatmap markers={recentUnique} /></div>}<div className="operationsLegend"><span><i className="legend-cyan" />DeliGo Eats · pedidos</span><span><i className="legend-violet" />SARCA · drivers/riders</span><span><i className="legend-orange" />DeliGo Market · encomendas</span><span><i className="legend-line" />Origem / destino</span></div></div></div><aside className="operationsSidePanel"><div className="operationsSideTitle"><h3>Operações activas</h3><small>{listItems.length} em leitura</small></div><div className="operationsList">{listItems.length ? pagination.items.map(item => <button key={item.kind + ":" + item.id} className={selected?.id === item.id || selected?.id.startsWith(item.id + ":") ? "selected" : ""} onClick={() => selectOnMap({ kind: item.kind, id: item.id })}><span style={{ color: item.color }} className={"operationGlyph " + (item.kind === "route" ? "route" : "entity")} dangerouslySetInnerHTML={{__html:item.glyph}} /><span><strong>{item.title}</strong><small>{item.subtitle}</small></span><em>{item.state}</em><b>›</b></button>) : <div className="operationsRoomNotice">Sem operações com coordenadas válidas nesta leitura.</div>}</div><nav className={styles.pagination} aria-label="Páginas de operações"><button disabled={pagination.page === 0} onClick={() => setPage(pagination.page - 1)}>Anterior</button><span>{pagination.page + 1} / {pagination.pages}</span><button disabled={pagination.page + 1 >= pagination.pages} onClick={() => setPage(pagination.page + 1)}>Seguinte</button></nav>{detail}</aside></div></> : <section className="operationsHistoryPanel"><div><h3>Histórico operacional</h3><p>Eventos históricos por período e plataforma. Esta vista não reconstrói posições GPS sem telemetria registada.</p></div>{history?.series?.length ? <div className="operationsHistoryList">{history.series.map(item => <button key={item.date} onClick={() => setSelected(null)}><strong>{item.date}</strong><span>{item.events} eventos · {item.deliveriesCompleted} entregas · {item.ridesCompleted} viagens · {item.cancellations} cancelamentos</span><b>Ver detalhes</b></button>)}</div> : <div className="operationsRoomNotice">Histórico indisponível para o período seleccionado.</div>}</section>}
  </section>;
}
