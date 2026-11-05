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
type TripAudit = {
  trip?: Record<string, unknown>;
  identification?: { tripId?: string; passenger?: Record<string, unknown>; driver?: Record<string, unknown>; vehicle?: Record<string, unknown> };
  locations?: { pickup?: Record<string, unknown>; dropoff?: Record<string, unknown>; stops?: unknown[] };
  schedule?: Record<string, unknown>;
  route?: { plannedCoordinates?: [number, number][]; actualCoordinates?: [number, number][]; riderCoordinates?: [number, number][]; points?: Array<Record<string, unknown>>; segments?: { toPickup?: Array<Record<string, unknown>>; trip?: Array<Record<string, unknown>> }; distanceMeters?: number; durationSeconds?: number; gaps?: Array<Record<string, unknown>> };
  values?: Record<string, unknown>;
  financial?: { reservations?: Array<Record<string, unknown>>; operations?: Array<Record<string, unknown>>; tollReconciliations?: Array<Record<string, unknown>> };
  occurrences?: { timeline?: Array<Record<string, unknown>>; incidents?: Array<Record<string, unknown>>; dispatchOffers?: Array<Record<string, unknown>> };
  telemetry?: { available?: boolean; pointCount?: number; driverPointCount?: number; riderPointCount?: number; gaps?: number };
};
type Replay = { coordinates: [number, number][]; progress: number; playing: boolean; speed: 1 | 2 | 4 };
type MapProfile = { platform: string; id: string; name: string };
const platforms = ["Todas as plataformas", "DeliGo", "SARCA", "DeliGo Market"];
const entities = ["Todas as entidades", "Pedidos", "Viagens", "Rotas", "Estafetas", "Drivers", "Riders", "Clientes", "Restaurantes"];
const statuses = ["Todos os estados", "Disponível", "Ocupado", "Em serviço", "Offline"];
const gpsStatusLabel = "GPS desactualizado";
const platformDistributionLabel = "Distribuição por plataforma";
const normalize = (value: string) => value.toLocaleLowerCase("pt-MZ").normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const platformName = (value: string) => value === "TaoMoz" ? "DeliGo Market" : value === "DeliGo Eats" ? "DeliGo" : value;
const statusName = (value?: string) => ({ disponivel: "Disponível", ocupado: "Ocupado", em_servico: "Em serviço", offline: "Offline", searching_driver: "A procurar motorista", accepted: "Aceite", assigned: "Atribuído", courier_assigned: "Estafeta atribuído", driver_assigned: "Motorista atribuído", driver_arriving: "Motorista a chegar", in_progress: "Em viagem", preparing: "Em preparação", ready_for_pickup: "Pronto para recolha", arrived: "Chegou ao local", in_transit: "Em trânsito", on_the_way: "Em entrega" }[value || ""] || value || "Não indicado");
const liveRouteStatuses = new Set(["in_progress", "in_service", "on_trip", "started", "active", "ongoing", "on_the_way", "out_for_delivery", "in_delivery", "delivering", "picked_up", "accepted", "assigned", "courier_assigned", "driver_assigned", "driver_arriving", "ready_for_pickup", "arrived", "in_transit"]);
const entityMatches = (marker: OperationsMapMarker, entity: string) => { if (entity === entities[0]) return true; const aliases: Record<string, string[]> = { Pedidos: ["pedido", "order", "delivery", "entrega"], Viagens: ["viagem", "trip", "ride"], Rotas: ["rota", "route"], Estafetas: ["estafeta", "courier", "entregador"], Drivers: ["driver", "motorista"], Riders: ["rider", "passageiro"], Clientes: ["cliente", "customer", "client"], Restaurantes: ["restaurante", "restaurant"] }; return (aliases[entity] || []).some(alias => normalize((marker.role || "") + " " + (marker.service || "")).includes(alias)); };
const auditTime = (value: unknown) => value ? new Date(String(value)).toLocaleString("pt-MZ", { dateStyle: "short", timeStyle: "short" }) : "—";
const auditMoney = (value: unknown, currency = "MZN") => value == null ? "—" : `${(Number(value) / 100).toFixed(2)} ${currency}`;

export function OperationsMapDashboard({ onOpenProfile }: { onOpenProfile?: (profile: MapProfile) => void }) {
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
  const [tripAudit, setTripAudit] = useState<TripAudit | null>(null);
  const [tripAuditError, setTripAuditError] = useState("");
  const [replay, setReplay] = useState<Replay | null>(null);
  const replayTimer = useRef<number | null>(null);
  const stopReplay = useCallback(() => { if (replayTimer.current) { window.clearInterval(replayTimer.current); replayTimer.current = null; } setReplay(null); }, []);
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
    let disposed = false;let timer: ReturnType<typeof window.setTimeout>;
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
  const filteredRoutes = useMemo(() => routes.filter(route => liveRouteStatuses.has(String(route.operationStatus || "").toLowerCase()) && route.coordinates.length >= 2 && (platform === platforms[0] || platformName(route.platform) === platform) && (entity === entities[0] || ["Pedidos", "Viagens", "Rotas"].includes(entity)) && (status === statuses[0] || status === "Em serviço" || statusName(route.operationStatus) === status) && normalize(route.label + " " + route.platform + " " + (route.workerName || "") + " " + (route.origin || "") + " " + (route.destination || "")).includes(normalize(search))), [entity, platform, routes, search, status]);
  const visibleRoutes = filteredRoutes;
  const recentUnique = useMemo(() => { const seen = new Set<string>(); return visibleMarkers.filter(marker => { if (marker.locationKind && marker.locationKind !== "gps") return false;const time = Date.parse(marker.updatedAt); if (!Number.isFinite(time) || Date.now() - time > 600000) return false; const key = marker.workerId || marker.service || marker.id; if (seen.has(key)) return false; seen.add(key); return true; }); }, [visibleMarkers]);
  const unavailable = payload?.sourceStatus === "unavailable" && markers.length === 0; const selectedMarker = selected?.kind === "marker" ? visibleMarkers.find(marker => marker.id === selected.id) : undefined; const selectedRoute = selected?.kind === "route" ? filteredRoutes.find(route => route.id === selected.id) : selectedMarker ? filteredRoutes.find(route=>selectedMarker.id.startsWith(route.id+":")) : undefined;
  const mapMarkers=useMemo(()=>cleanMapMarkers(visibleMarkers,selectedRoute?.id),[visibleMarkers,selectedRoute?.id]);
  const listItems = useMemo(() => [
    ...filteredRoutes.map(route => { const driver = visibleMarkers.find(marker => marker.id.startsWith(route.id + ":") && /driver|motorista|estafeta|entregador/i.test(marker.role));return { id: route.id, kind: "route" as const, title: route.label, subtitle: platformName(route.platform), state: statusName(route.operationStatus || "em_servico"), glyph: markerIconSvg("motorista", route.platform), color: mapColor(route.platform) }; }),
    ...visibleMarkers.filter(marker => !/cliente|restaurante|loja/i.test(marker.role) && ["em_servico", "ocupado"].includes(marker.status || "") && !filteredRoutes.some(route => marker.id.startsWith(route.id + ":"))).map(marker => ({ id: marker.id, kind: "marker" as const, title: marker.service || marker.role, subtitle: platformName(marker.platform), state: statusName(marker.status), glyph: markerIconSvg(marker.role, marker.platform), color: mapColor(marker.platform) })),
  ], [visibleMarkers, filteredRoutes]);
  const initialSelection=useRef(false);
  useEffect(()=>{if(!initialSelection.current&&listItems.length){initialSelection.current=true;setSelected({kind:listItems[0].kind,id:listItems[0].id})}},[listItems]);
  const pagination = pageOperations(listItems, page);
  const selectOnMap = useCallback((value: Selection) => {
    setSelected(value);setFollowing(false);
    const index = listItems.findIndex(item => item.id === value.id || value.id.startsWith(item.id + ":"));if (index >= 0) setPage(Math.floor(index / mapPageSize));
    if (value.kind === "marker" && onOpenProfile) {
      const marker = markers.find(item => item.id === value.id);
      const id = marker?.profileId || marker?.workerId;
      if (id) {
        const raw = String(marker?.profilePlatform || marker?.platform || "").toLowerCase();
        const platform = raw.includes("market") || raw.includes("taomoz") ? "taomoz" : raw.includes("sarca") ? "sarca" : raw.includes("comun") ? "comunhao" : raw.includes("mestre") ? "mestre24" : "deligo";
        onOpenProfile({ platform, id: String(id), name: markerName(marker) });
      }
    }
  }, [listItems, markers, onOpenProfile]);
  const routeDriver = selectedRoute ? markers.find(marker => marker.id.startsWith(selectedRoute.id + ":") && /driver|motorista|estafeta|entregador/i.test(marker.role)) : undefined;
  const followedMarker = selectedMarker || routeDriver;
  const canFollow = Boolean(followedMarker && (!followedMarker.locationKind || followedMarker.locationKind === "gps"));
  const selectedTripId = useMemo(() => {
    const match = selected?.id.match(/^sarca:trip:([0-9a-f-]{36})(?::|$)/i);
    return match?.[1] || null;
  }, [selected]);
  useEffect(() => {
    stopReplay();
    setTripAudit(null);
    setTripAuditError("");
    if (!selectedTripId) return;
    const controller = new AbortController();
    void fetch(`/api/sarca/trips/${selectedTripId}`, { cache: "no-store", signal: controller.signal })
      .then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar a auditoria da viagem."); return body as TripAudit; })
      .then(body => { if (!controller.signal.aborted) setTripAudit(body); })
      .catch(reason => { if (!controller.signal.aborted) setTripAuditError(reason instanceof Error ? reason.message : "Não foi possível carregar a auditoria da viagem."); });
    return () => controller.abort();
  }, [selectedTripId, stopReplay]);
  useEffect(() => () => stopReplay(), [stopReplay]);
  const auditActual = tripAudit?.route?.actualCoordinates || [];
  const auditPlanned = tripAudit?.route?.plannedCoordinates || [];
  const auditMapRoutes = useMemo<OperationsMapRoute[]>(() => {
    if (!selectedTripId || !tripAudit) return filteredRoutes;
    const base = selectedRoute || { id: `sarca:trip:${selectedTripId}`, platform: "SARCA", label: "Viagem SARCA", coordinates: [], updatedAt: new Date().toISOString() };
    const next: OperationsMapRoute[] = [];
    if (auditPlanned.length >= 2) next.push({ ...base, id: `${base.id}:planned`, selectionId: base.id, kind: "planned", coordinates: auditPlanned });
    if (auditActual.length >= 2) next.push({ ...base, kind: "actual", coordinates: auditActual });
    if (!next.length && base.coordinates.length >= 2) next.push(base);
    return [...filteredRoutes.filter(route => route.id !== base.id), ...next];
  }, [auditActual, auditPlanned, filteredRoutes, selectedRoute, selectedTripId, tripAudit]);
  const startReplay = useCallback((speed: 1 | 2 | 4 = 1, initialProgress = 0) => {
    if (auditActual.length < 2) return;
    stopReplay();
    let progress = Math.min(1, Math.max(0, initialProgress));
    setReplay({ coordinates: auditActual, progress, playing: true, speed });
    replayTimer.current = window.setInterval(() => {
      progress = Math.min(1, progress + (0.02 * speed));
      setReplay({ coordinates: auditActual, progress, playing: progress < 1, speed });
      if (progress >= 1 && replayTimer.current) { window.clearInterval(replayTimer.current); replayTimer.current = null; }
    }, Math.max(90, Math.round(350 / speed)));
  }, [auditActual, stopReplay]);
  const pauseReplay = useCallback(() => {
    if (replayTimer.current) { window.clearInterval(replayTimer.current); replayTimer.current = null; }
    setReplay(value => value ? { ...value, playing: false } : value);
  }, []);
  const resumeReplay = useCallback(() => {
    if (!replay) return;
    if (replay.progress >= 1) return startReplay(replay.speed, 0);
    startReplay(replay.speed, replay.progress);
  }, [replay, startReplay]);
  const stepReplay = useCallback((direction: 1 | -1) => {
    if (!replay || replay.coordinates.length < 2) return;
    pauseReplay();
    const step = 1 / (replay.coordinates.length - 1);
    setReplay({ ...replay, progress: Math.min(1, Math.max(0, replay.progress + direction * step)), playing: false });
  }, [pauseReplay, replay]);
  const kpis = [["Entregas activas",filteredRoutes.filter(route=>["DeliGo","DeliGo Market"].includes(platformName(route.platform))).length,"cyan"],["Viagens em curso",filteredRoutes.filter(route=>platformName(route.platform)==="SARCA").length,"violet"],["Disponíveis",mapMarkers.filter(marker=>marker.status==="disponivel").length,"green"],["Sem sinal recente",mapMarkers.filter(marker=>(!marker.locationKind||marker.locationKind==="gps")&&(!Number.isFinite(Date.parse(marker.updatedAt))||Date.now()-Date.parse(marker.updatedAt)>600000)).length,"orange"]];
  const detail = (selectedMarker || selectedRoute) ? <div className="operationDetail"><div className="operationDetailHead"><div><span>SELECIONADO</span><strong>{selectedMarker ? markerName(selectedMarker) : selectedRoute?.label}</strong></div><button aria-label="Fechar detalhes" onClick={() => { setSelected(null);setFollowing(false);stopReplay(); }}>×</button></div><p>{selectedRoute ? platformName(selectedRoute.platform) : selectedMarker?.role + " · " + platformName(selectedMarker?.platform || "")}</p><dl>
    <dt>Responsável</dt><dd>{followedMarker?.workerName || selectedRoute?.workerName || "Sem responsável identificado"}</dd>
    <dt>Estado</dt><dd>{selectedMarker ? statusName(selectedMarker.status) : statusName(selectedRoute?.operationStatus || "em_servico")}</dd>
    {(selectedMarker?.origin || selectedRoute?.origin) && <><dt>Origem</dt><dd>{selectedMarker?.origin || selectedRoute?.origin}</dd></>}
    {(selectedMarker?.destination || selectedRoute?.destination) && <><dt>Destino</dt><dd>{selectedMarker?.destination || selectedRoute?.destination}</dd></>}
    {followedMarker && <><dt>{followedMarker.locationKind === "endpoint" ? "Ponto registado" : "Última posição"}</dt><dd>{new Date(followedMarker.updatedAt).toLocaleTimeString("pt-MZ")}{(!followedMarker.locationKind || followedMarker.locationKind === "gps") && Date.now() - Date.parse(followedMarker.updatedAt) > 60000 ? " · " + gpsStatusLabel : ""}</dd></>}
    {selectedRoute && <><dt>Pontos</dt><dd>{selectedRoute.coordinates.length === 2 ? "Origem e destino" : `${selectedRoute.coordinates.length} posições registadas`}</dd></>}
    </dl><button className="operationFollow" disabled={!canFollow} onClick={() => setFollowing(value => !value)}>{following ? "Parar acompanhamento" : "Acompanhar no mapa"}</button>
    {selectedTripId && tripAudit && <section className="tripAuditPanel" aria-label="Auditoria da viagem SARCA"><div className="tripAuditHead"><div><span>AUDITORIA SARCA</span><strong>Viagem {selectedTripId.slice(0, 8)}</strong></div><div className="tripAuditActions"><button className="operationFollow" disabled={auditActual.length < 2} onClick={() => replay?.playing ? pauseReplay() : resumeReplay()}>{replay?.playing ? "Pausar" : replay ? "Continuar" : "Reproduzir percurso"}</button>{replay && <><button className="operationFollow" onClick={() => stepReplay(-1)} aria-label="Retroceder um ponto">◀</button><button className="operationFollow" onClick={() => stepReplay(1)} aria-label="Avançar um ponto">▶</button><select aria-label="Velocidade de reprodução" value={replay.speed} onChange={event => startReplay(Number(event.target.value) as 1 | 2 | 4, replay.progress)}><option value={1}>1×</option><option value={2}>2×</option><option value={4}>4×</option></select><button className="operationFollow" onClick={stopReplay}>Fechar reprodução</button></>}<a className="operationFollow" href={`/api/sarca/trips/${selectedTripId}?export=1`} download={`sarca-trip-${selectedTripId}.json`}>Exportar auditoria</a></div></div>
      <div className="tripAuditGrid"><div><b>Passageiro</b><span>{String(tripAudit.identification?.passenger?.name || "Não identificado")}</span></div><div><b>Motorista</b><span>{String(tripAudit.identification?.driver?.name || "Não identificado")}</span></div><div><b>Veículo / matrícula</b><span>{[tripAudit.identification?.vehicle?.make, tripAudit.identification?.vehicle?.model, tripAudit.identification?.vehicle?.plateNumber].filter(Boolean).join(" · ") || "Não registado"}</span></div><div><b>Pagamento</b><span>{String(tripAudit.values?.paymentStatus || "Não indicado")} · {String(tripAudit.values?.paymentMethod || "—")}</span></div></div>
      <div className="tripAuditSection"><b>Locais confirmados</b><span>Recolha: {String(tripAudit.locations?.pickup?.address || "—")}</span><span>Destino: {String(tripAudit.locations?.dropoff?.address || "—")}</span><small>{String(tripAudit.locations?.pickup?.latitude ?? "—")}, {String(tripAudit.locations?.pickup?.longitude ?? "—")} → {String(tripAudit.locations?.dropoff?.latitude ?? "—")}, {String(tripAudit.locations?.dropoff?.longitude ?? "—")}</small></div>
      <div className="tripAuditSection"><b>Linha do tempo</b>{Object.entries(tripAudit.schedule || {}).map(([key, value]) => <span key={key}><em>{key.replace(/([A-Z])/g, " $1")}</em>{auditTime(value)}</span>)}</div>
      <div className="tripAuditSection"><b>Rota e valores</b><span>Rota prevista: {auditPlanned.length ? `${auditPlanned.length} pontos` : "não registada"} · rota GPS real: {tripAudit.telemetry?.driverPointCount || 0} pontos</span><span>Distância real: {tripAudit.route?.distanceMeters ? `${Math.round(tripAudit.route.distanceMeters)} m` : "—"} · falhas: {tripAudit.route?.gaps?.length || tripAudit.telemetry?.gaps || 0}</span><span>Estimado: {auditMoney(tripAudit.values?.estimatedFareMinor, String(tripAudit.values?.currency || "MZN"))} · final: {auditMoney(tripAudit.values?.finalFareMinor, String(tripAudit.values?.currency || "MZN"))} · comissão: {auditMoney(tripAudit.values?.commissionMinor, String(tripAudit.values?.currency || "MZN"))}</span><span>Corrida sem portagem: {auditMoney(tripAudit.values?.commissionableFareMinor, String(tripAudit.values?.currency || "MZN"))} · portagens: {auditMoney(tripAudit.values?.tollAmountMinor, String(tripAudit.values?.currency || "MZN"))}</span><span>Pagamento: {String(tripAudit.values?.paymentMethod || "—")} · fundos: {String(tripAudit.values?.fundsStatus || "—")} · reservas: {tripAudit.financial?.reservations?.length || 0} · operações idempotentes: {tripAudit.financial?.operations?.length || 0}</span>{tripAudit.financial?.tollReconciliations?.map((item, index) => <span key={String(item.id || index)}>Reconciliação de portagem: {auditMoney(item.toll_amount_minor, String(tripAudit.values?.currency || "MZN"))} · {String(item.payment_channel || "unknown")} · {auditTime(item.created_at)}</span>)}</div>
      <div className="tripAuditSection"><b>Telemetria por fase</b><span>Deslocação para recolha: {tripAudit.route?.segments?.toPickup?.length || 0} pontos</span><span>Viagem com passageiro: {tripAudit.route?.segments?.trip?.length || 0} pontos</span><span>Localização do passageiro partilhada: {tripAudit.telemetry?.riderPointCount || 0} posições</span><span>{(tripAudit.route?.gaps?.length || tripAudit.telemetry?.gaps) ? "Sem sinal indicado nos intervalos sem GPS." : "Sem intervalos de sinal assinalados."}</span></div>
      {tripAudit.occurrences?.incidents?.length ? <div className="tripAuditSection"><b>Ocorrências</b>{tripAudit.occurrences.incidents.map((incident, index) => <span key={String(incident.id || index)}>{String(incident.incident_type || incident.type || "Ocorrência")} · {String(incident.status || "aberta")} · {auditTime(incident.created_at)}</span>)}</div> : <div className="tripAuditSection"><b>Ocorrências</b><span>Nenhuma ocorrência registada.</span></div>}
    </section>}
    {selectedTripId && tripAuditError && <p className="operationsRoomNotice error">{tripAuditError}</p>}
    </div> : null;
  return <section className={`operationsControlRoom ${styles.room}`}><header className="operationsRoomHeader"><div className="operationsRoomTitle"><span className="operationsRoomEyebrow">CENTRAL HQ · MAPAS E ACOMPANHAMENTO</span><h2>Centro de Operações <i>● Ao vivo</i></h2><p>Mapas e acompanhamento</p></div><div className="operationsRoomHeaderActions"><small>{payload?.checkedAt ? "Actualizado " + new Date(payload.checkedAt).toLocaleTimeString("pt-MZ") : "A preparar leitura"}</small><span className="operationsViewTabs"><button className={view === "live" ? "active" : ""} onClick={() => setView("live")}>Ao vivo</button><button className={view === "history" ? "active" : ""} onClick={() => setView("history")}>Histórico</button></span><button onClick={() => void load()}>↻ Actualizar</button></div></header>
    <div className="operationsPlatformTabs" aria-label="Plataforma">{platforms.map(item => <button key={item} className={platform === item ? "active" : ""} onClick={() => { setPlatform(item);setPage(0);setSelected(null);setFollowing(false); }}>{item === platforms[0]?"Todas":item === "DeliGo" ? "DeliGo Eats" : item}</button>)}</div><div className="operationsRoomFilters"><input aria-label="Pesquisar pedido, viagem ou pessoa" value={search} onChange={event => { setSearch(event.target.value);setPage(0); }} placeholder="⌕  Pesquisar pedido, viagem ou pessoa…" /><label>Estado<select value={status} onChange={event => { setStatus(event.target.value);setPage(0); }}>{statuses.map(item => <option key={item}>{item}</option>)}</select></label><label>Entidade<select value={entity} onChange={event => { setEntity(event.target.value);setPage(0); }}>{entities.map(item => <option key={item}>{item}</option>)}</select></label></div>{view === "history" && <DashboardFilters value={filters} onChange={setFilters} platforms={[]} />}{error && <div className="operationsRoomNotice error">{error}</div>}
    {view === "history" && <div className="operationsKpis">{kpis.map(([label, value, color]) => <article className={String(color)} key={String(label)}><span>{label}</span><strong>{error || unavailable ? "—" : value}</strong></article>)}</div>}
    {view === "live" ? <><div className="operationsRoomGrid"><div className={styles.mapColumn}><div className="operationsKpis">{kpis.map(([label, value, color]) => <article className={String(color)} key={String(label)}><span>{label}</span><strong>{error || unavailable ? "—" : value}</strong></article>)}</div><div ref={room} className={`operationsMapStage ${fullscreen ? styles.mapFullscreen : ""}`}><div className="operationsMapStageHead"><div><strong>Operações no mapa</strong><small>{mapMarkers.length} posições · seleccione um ícone para ver detalhes</small></div><div className="operationsMapControls"><button onClick={() => void toggleFullscreen()}>{fullscreen ? "Sair da tela cheia" : "Tela cheia"}</button><button onClick={() => { setFollowing(false);setRecenterKey(value => value + 1); }}>Recentrar</button><span>{unavailable ? "Fonte GPS indisponível" : "Dados autorizados"}</span></div></div>{payload ? <LiveOperationsMap markers={mapMarkers} routes={auditMapRoutes} replay={replay} onSelect={selectOnMap} selected={selected} following={following} followId={followedMarker?.id} recenterKey={recenterKey} /> : <div className="operationsMapEmpty">A preparar o mapa…</div>}{densityOpen && <div className="operationsDensityPanel"><strong>Densidade de posições recentes</strong><small>Uma posição por entidade · últimos 10 minutos</small><OperationsDensityHeatmap markers={recentUnique} /></div>}<div className="operationsLegend"><span><i className="legend-cyan" />DeliGo Eats · pedidos</span><span><i className="legend-violet" />SARCA · drivers/riders</span><span><i className="legend-orange" />DeliGo Market · encomendas</span><span><i className="legend-line" />Rota prevista / GPS real</span></div></div></div><aside className="operationsSidePanel"><div className="operationsSideTitle"><h3>Operações activas</h3><small>{listItems.length} em leitura</small></div><div className="operationsList">{listItems.length ? pagination.items.map(item => <button key={item.kind + ":" + item.id} className={selected?.id === item.id || selected?.id.startsWith(item.id + ":") ? "selected" : ""} onClick={() => selectOnMap({ kind: item.kind, id: item.id })}><span style={{ color: item.color }} className={"operationGlyph " + (item.kind === "route" ? "route" : "entity")} dangerouslySetInnerHTML={{__html:item.glyph}} /><span><strong>{item.title}</strong><small>{item.subtitle}</small></span><em>{item.state}</em><b>›</b></button>) : <div className="operationsRoomNotice">Sem operações com coordenadas válidas nesta leitura.</div>}</div><nav className={styles.pagination} aria-label="Páginas de operações"><button disabled={pagination.page === 0} onClick={() => setPage(pagination.page - 1)}>Anterior</button><span>{pagination.page + 1} / {pagination.pages}</span><button disabled={pagination.page + 1 >= pagination.pages} onClick={() => setPage(pagination.page + 1)}>Seguinte</button></nav>{detail}</aside></div></> : <section className="operationsHistoryPanel"><div><h3>Histórico operacional</h3><p>Eventos históricos por período e plataforma. Esta vista não reconstrói posições GPS sem telemetria registada.</p></div>{history?.series?.length ? <div className="operationsHistoryList">{history.series.map(item => <button key={item.date} onClick={() => setSelected(null)}><strong>{item.date}</strong><span>{item.events} eventos · {item.deliveriesCompleted} entregas · {item.ridesCompleted} viagens · {item.cancellations} cancelamentos</span><b>Ver detalhes</b></button>)}</div> : <div className="operationsRoomNotice">Histórico indisponível para o período seleccionado.</div>}</section>}
  </section>;
}
