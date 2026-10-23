"use client";

import { useEffect, useMemo, useState } from "react";
import LiveOperationsMap, { type OperationsMapMarker } from "@/components/LiveOperationsMap";
import { ChartContainer } from "./ChartContainer";
import { EmptyState } from "./EmptyState";
import { DashboardHeader } from "./DashboardHeader";

type MapPayload = { checkedAt?: string; markers?: OperationsMapMarker[] };

const platformLabel = (platform: string) => platform === "TaoMoz" ? "DeliGo Market" : platform;
const statusLabel = (status: string) => ({ disponivel: "Disponível", ocupado: "Ocupado", em_servico: "Em serviço", offline: "Offline" }[status] || status || "Não indicado");

export function OperationsMapDashboard() {
  const [payload, setPayload] = useState<MapPayload | null>(null);
  const [error, setError] = useState("");
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [status, setStatus] = useState("todos");
  const [search, setSearch] = useState("");

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const response = await fetch("/api/map", { cache: "no-store" });
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(String(body.error || "Mapa operacional indisponível."));
        if (!cancelled) { setPayload(body); setError(""); }
      } catch (reason) {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "Mapa operacional indisponível.");
      }
    };
    void load();
    const timer = window.setInterval(() => void load(), 10_000);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, []);

  const markers = Array.isArray(payload?.markers) ? payload!.markers! : [];
  const filtered = useMemo(() => markers.filter(marker => {
    const matchesPlatform = platform === "Todas as plataformas" || platformLabel(marker.platform) === platform;
    const matchesStatus = status === "todos" || marker.status === status;
    const haystack = `${marker.workerName || ""} ${marker.workerId || ""} ${marker.role} ${platformLabel(marker.platform)}`.toLocaleLowerCase("pt");
    return matchesPlatform && matchesStatus && haystack.includes(search.toLocaleLowerCase("pt"));
  }), [markers, platform, status, search]);

  const platforms = useMemo(() => Array.from(new Set(markers.map(marker => platformLabel(marker.platform))).values()).sort((a, b) => a.localeCompare(b, "pt")), [markers]);
  const byPlatform = useMemo(() => platforms.map(label => ({ label, value: markers.filter(marker => platformLabel(marker.platform) === label).length })), [markers, platforms]);
  const byStatus = useMemo(() => ["disponivel", "ocupado", "em_servico", "offline"].map(value => ({ label: statusLabel(value), value: markers.filter(marker => marker.status === value).length })).filter(item => item.value > 0), [markers]);
  const stale = markers.filter(marker => { const timestamp = Date.parse(marker.updatedAt); return Number.isFinite(timestamp) && Date.now() - timestamp > 5 * 60_000; }).length;
  const maxPlatform = Math.max(1, ...byPlatform.map(item => item.value));
  const maxStatus = Math.max(1, ...byStatus.map(item => item.value));

  return <section className="analyticsDashboardShell operationsMapDashboard">
    <DashboardHeader title="Centro de Mapas" description="Mapa operacional e métricas agregadas para trabalhadores autenticados da Central." updatedAt={payload?.checkedAt ? new Date(payload.checkedAt).toLocaleString("pt-MZ") : undefined} />
    <div className="analyticsFilters" aria-label="Filtros do mapa"><label><span>Plataforma</span><select value={platform} onChange={event => setPlatform(event.target.value)}><option>Todas as plataformas</option>{platforms.map(item => <option key={item}>{item}</option>)}</select></label><label><span>Estado</span><select value={status} onChange={event => setStatus(event.target.value)}><option value="todos">Todos os estados</option><option value="disponivel">Disponível</option><option value="ocupado">Ocupado</option><option value="em_servico">Em serviço</option><option value="offline">Offline</option></select></label><label><span>Pesquisar</span><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Nome, função ou plataforma" /></label></div>
    {error ? <EmptyState title="Mapa operacional indisponível" description={error} /> : <>
      <div className="analyticsKpiGrid"><article className="analyticsKpiCard analyticsStatus-fresh"><span>Marcadores visíveis</span><strong>{filtered.length}</strong><small>Fonte autorizada · filtro actual</small></article><article className="analyticsKpiCard analyticsStatus-fresh"><span>Plataformas com dados</span><strong>{platforms.length}</strong><small>Sem inventar posições ausentes</small></article><article className={`analyticsKpiCard ${stale ? "analyticsStatus-stale" : "analyticsStatus-fresh"}`}><span>GPS desactualizado</span><strong>{stale}</strong><small>Mais de 5 minutos desde a actualização</small></article><article className="analyticsKpiCard analyticsStatus-fresh"><span>Última leitura</span><strong>{payload?.checkedAt ? new Date(payload.checkedAt).toLocaleTimeString("pt-MZ") : "—"}</strong><small>Actualização automática a cada 10 s</small></article></div>
      <div className="analyticsExecutiveGrid"><ChartContainer title="Mapa operacional" description="A localização só aparece quando a fonte autorizada devolve coordenadas recentes.">{payload ? <LiveOperationsMap markers={filtered} /> : <div className="analyticsMapLoading">A carregar posições autorizadas…</div>}</ChartContainer><ChartContainer title="Distribuição por plataforma" description="Contagem dos marcadores devolvidos pelo backend."><div className="analyticsBarList">{byPlatform.length ? byPlatform.map(item => <div className="analyticsBarRow" key={item.label}><div><strong>{item.label}</strong><small>Marcadores</small></div><span><i style={{ width: `${Math.max(3, item.value / maxPlatform * 100)}%` }} /><b>{item.value}</b></span></div>) : <EmptyState title="Sem posições disponíveis" description="Nenhuma plataforma devolveu coordenadas verificáveis." />}</div></ChartContainer></div>
      <ChartContainer title="Estados operacionais" description="Resumo dos estados presentes na leitura actual."><div className="analyticsBarList">{byStatus.length ? byStatus.map(item => <div className="analyticsBarRow" key={item.label}><div><strong>{item.label}</strong><small>Marcadores</small></div><span><i style={{ width: `${Math.max(3, item.value / maxStatus * 100)}%` }} /><b>{item.value}</b></span></div>) : <EmptyState title="Estados indisponíveis" description="A fonte não devolveu estados operacionais." />}</div></ChartContainer>
      <p className="analyticsDataNote">Acesso limitado a sessões corporativas autenticadas. O mapa é somente leitura neste painel; reatribuições e outras ações operacionais continuam sujeitas às permissões específicas.</p>
    </>}
  </section>;
}
