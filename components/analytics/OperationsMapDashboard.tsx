"use client";

import { useEffect, useMemo, useState } from "react";
import LiveOperationsMap, { type OperationsMapMarker } from "@/components/LiveOperationsMap";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { EmptyState } from "./EmptyState";
import type { AnalyticsFilters } from "@/lib/analytics-contracts";
import { DashboardHeader } from "./DashboardHeader";
import { OperationsDensityHeatmap } from "./OperationsDensityHeatmap";

type MapPayload = { checkedAt?: string; markers?: OperationsMapMarker[] };
type HistoryPayload = { series: Array<{ date: string; events: number; created: number; statusChanges: number; cancellations: number; deliveriesCompleted: number; ridesCompleted: number }>; totals?: { deliveriesCompleted?: number; ridesCompleted?: number }; comparison?: { events?: { current: number; previous: number; changePercent: number | null }; deliveriesCompleted?: { current: number; previous: number; changePercent: number | null }; ridesCompleted?: { current: number; previous: number; changePercent: number | null } }; limitations?: string[] };

const platformLabel = (platform: string) => platform === "TaoMoz" ? "DeliGo Market" : platform;
const statusLabel = (status: string) => ({ disponivel: "Disponível", ocupado: "Ocupado", em_servico: "Em serviço", offline: "Offline" }[status] || status || "Não indicado");
const entityOptions = ["Pedidos", "Estafetas", "Drivers", "Riders", "Clientes", "Restaurantes"];
const normalizeEntity = (value: string) => value.toLocaleLowerCase("pt").normalize("NFD").replace(/[\u0300-\u036f]/g, "");
const entityMatches = (role: string, entity: string) => {
  if (entity === "todos") return true;
  const normalized = normalizeEntity(role);
  const aliases: Record<string, string[]> = {
    Pedidos: ["pedido", "order", "delivery", "entrega", "service_request"],
    Estafetas: ["estafeta", "courier", "entregador"],
    Drivers: ["driver", "motorista"],
    Riders: ["rider", "passageiro"],
    Clientes: ["cliente", "customer", "client", "user"],
    Restaurantes: ["restaurante", "restaurant"],
  };
  return (aliases[entity] || []).some(alias => normalized.includes(alias));
};

export function OperationsMapDashboard() {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<MapPayload | null>(null);
  const [error, setError] = useState("");
  const [history, setHistory] = useState<HistoryPayload | null>(null);
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [entity, setEntity] = useState("todos");
  const [status, setStatus] = useState("todos");
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const historyParams = new URLSearchParams({ period: filters.period });
        if (filters.from) historyParams.set("from", filters.from);
        if (filters.to) historyParams.set("to", filters.to);
        const [response, historyResponse] = await Promise.all([fetch("/api/map", { cache: "no-store" }), fetch(`/api/analytics/map?${historyParams.toString()}`, { cache: "no-store" })]);
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(String(body.error || "Mapa operacional indisponível."));
        const historyBody = await historyResponse.json().catch(() => ({}));
        if (!cancelled) { setPayload(body); setHistory(historyResponse.ok ? historyBody : null); setError(""); }
      } catch (reason) {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "Mapa operacional indisponível.");
      }
    };
    void load();
    const timer = window.setInterval(() => void load(), 10_000);
    return () => { cancelled = true; window.clearInterval(timer); };
    }, [filters.period, filters.from, filters.to]);

  const markers = Array.isArray(payload?.markers) ? payload!.markers! : [];
  const filtered = useMemo(() => markers.filter(marker => {
    const matchesPlatform = platform === "Todas as plataformas" || platformLabel(marker.platform) === platform;
    const matchesEntity = entityMatches(String(marker.role || ""), entity);
    const matchesStatus = status === "todos" || marker.status === status;
    const haystack = `${marker.workerName || ""} ${marker.workerId || ""} ${marker.role} ${platformLabel(marker.platform)}`.toLocaleLowerCase("pt");
    return matchesPlatform && matchesEntity && matchesStatus && haystack.includes(search.toLocaleLowerCase("pt"));
  }), [markers, platform, entity, status, search]);

  const platforms = useMemo(() => Array.from(new Set(markers.map(marker => platformLabel(marker.platform))).values()).sort((a, b) => a.localeCompare(b, "pt")), [markers]);
  const byPlatform = useMemo(() => platforms.map(label => ({ label, value: markers.filter(marker => platformLabel(marker.platform) === label).length })), [markers, platforms]);
  const byStatus = useMemo(() => ["disponivel", "ocupado", "em_servico", "offline"].map(value => ({ label: statusLabel(value), value: markers.filter(marker => marker.status === value).length })).filter(item => item.value > 0), [markers]);
  const stale = markers.filter(marker => { const timestamp = Date.parse(marker.updatedAt); return Number.isFinite(timestamp) && Date.now() - timestamp > 5 * 60_000; }).length;
  const maxPlatform = Math.max(1, ...byPlatform.map(item => item.value));
  const maxStatus = Math.max(1, ...byStatus.map(item => item.value));
  const maxHistory = Math.max(1, ...(history?.series || []).map(item => item.events));

  return <section className="analyticsDashboardShell operationsMapDashboard">
    <DashboardHeader title="Centro de Mapas" description="Mapa operacional e métricas agregadas para trabalhadores autenticados da Central." updatedAt={payload?.checkedAt ? new Date(payload.checkedAt).toLocaleString("pt-MZ") : undefined} />
      <DashboardFilters value={filters} onChange={setFilters} platforms={platforms} /><div className="analyticsFilters" aria-label="Filtros do mapa"><label><span>Plataforma</span><select value={platform} onChange={event => setPlatform(event.target.value)}><option>Todas as plataformas</option>{platforms.map(item => <option key={item}>{item}</option>)}</select></label><label><span>Ver</span><select value={entity} onChange={event => setEntity(event.target.value)}><option value="todos">Todas as entidades</option>{entityOptions.map(item => <option key={item} value={item}>{item}</option>)}</select></label><label><span>Estado</span><select value={status} onChange={event => setStatus(event.target.value)}><option value="todos">Todos os estados</option><option value="disponivel">Disponível</option><option value="ocupado">Ocupado</option><option value="em_servico">Em serviço</option><option value="offline">Offline</option></select></label><label><span>Pesquisar</span><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome, função ou plataforma" /></label></div>
    {error ? <EmptyState title="Mapa operacional indisponível" description={error} /> : <>
      <div className="analyticsKpiGrid"><article className="analyticsKpiCard analyticsStatus-fresh"><span>Operações activas</span><strong>{filtered.length}</strong><small>Marcadores actuais · GPS desactualizado: {stale}</small></article><article className="analyticsKpiCard analyticsStatus-fresh"><span>Entregas concluídas · 30 dias</span><strong>{history?.totals?.deliveriesCompleted ?? "Indisponível"}</strong><small>Eventos DeliGo de conclusão verificáveis</small></article><article className="analyticsKpiCard analyticsStatus-fresh"><span>Viagens SARCA · 30 dias</span><strong>{history?.totals?.ridesCompleted ?? "Indisponível"}</strong><small>Eventos SARCA concluídos verificáveis</small></article><article className="analyticsKpiCard analyticsStatus-unavailable"><span>Distância percorrida</span><strong>Indisponível</strong><small>Telemetria histórica insuficiente</small></article></div>
      <div className="analyticsExecutiveGrid"><ChartContainer title="Mapa operacional" description="A localização só aparece quando a fonte autorizada devolve coordenadas recentes.">{payload ? <LiveOperationsMap markers={filtered} /> : <div className="analyticsMapLoading">A carregar posições autorizadas…</div>}</ChartContainer><ChartContainer title="Distribuição por plataforma" description="Contagem dos marcadores devolvidos pelo backend."><div className="analyticsBarList">{byPlatform.length ? byPlatform.map(item => <div className="analyticsBarRow" key={item.label}><div><strong>{item.label}</strong><small>Marcadores</small></div><span><i style={{ width: `${Math.max(3, item.value / maxPlatform * 100)}%` }} /><b>{item.value}</b></span></div>) : <EmptyState title="Sem posições disponíveis" description="Nenhuma plataforma devolveu coordenadas verificáveis." />}</div></ChartContainer></div>
      <ChartContainer title="Heatmap de posições atuais" description="Densidade das coordenadas autorizadas na leitura atual; não representa pedidos históricos nem rotas. "><OperationsDensityHeatmap markers={filtered} /></ChartContainer>
      <ChartContainer title="Estados operacionais" description="Resumo dos estados presentes na leitura actual."><div className="analyticsBarList">{byStatus.length ? byStatus.map(item => <div className="analyticsBarRow" key={item.label}><div><strong>{item.label}</strong><small>Marcadores</small></div><span><i style={{ width: `${Math.max(3, item.value / maxStatus * 100)}%` }} /><b>{item.value}</b></span></div>) : <EmptyState title="Estados indisponíveis" description="A fonte não devolveu estados operacionais." />}</div></ChartContainer>
      <ChartContainer title="Actividade operacional histórica" description="Eventos reais de hq.platform_events · últimos 30 dias versus período anterior.">{history?.series?.length ? <div className="analyticsBarList">{history.series.map(item => <div className="analyticsBarRow" key={item.date}><div><strong>{item.date}</strong><small>{item.deliveriesCompleted} entregas · {item.ridesCompleted} viagens · {item.cancellations} cancelamentos</small></div><span><i style={{ width: `${Math.max(2, item.events / maxHistory * 100)}%` }} /><b>{item.events}</b></span></div>)}</div> : <EmptyState title="Histórico indisponível" description="Não existe uma fonte histórica operacional verificável neste momento." />}</ChartContainer>
      <p className="analyticsDataNote">Acesso limitado a sessões corporativas autenticadas. O mapa é somente leitura neste painel; reatribuições e outras ações operacionais continuam sujeitas às permissões específicas.</p>
    </>}
  </section>;
}
