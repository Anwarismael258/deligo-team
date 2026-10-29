import { useEffect, useState } from "react";
import type { AnalyticsFilters, KPIResult } from "@/lib/analytics-contracts";
import { AnalyticsDataTable } from "./AnalyticsDataTable";
import { ChartContainer } from "./ChartContainer";
import { DashboardFilters } from "./DashboardFilters";
import { DashboardHeader } from "./DashboardHeader";
import { EmptyState } from "./EmptyState";
import { KPIGrid } from "./KPIGrid";
import { AnalyticsBarChart, AnalyticsLineChart } from "./AnalyticsCharts";

type Mode = "marketing" | "inbox";
type Breakdown = Array<{ label: string; value: number }>;
type Data = { range?: { from: string; to: string }; data?: Record<string, unknown> & { byStatus?: Breakdown; byChannel?: Breakdown; byPlatform?: Breakdown; byType?: Breakdown; series?: Array<{ date: string; value: number }>; filters?: { platforms?: string[]; channels?: string[]; statuses?: string[]; eventTypes?: string[] } }; limitations?: string[] };
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const rows = (items?: Breakdown) => (items || []).map(item => ({ id: item.label, label: item.label, total: item.value }));
const filterLabel = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, character => character.toUpperCase());

export function CommunicationAnalyticsDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<Data | null>(null); const [error, setError] = useState("");
  useEffect(() => { const params = new URLSearchParams({ mode, period: filters.period }); if (filters.from) params.set("from", filters.from); if (filters.to) params.set("to", filters.to); if (filters.platform) params.set("platform", filters.platform); if (filters.channel) params.set("channel", filters.channel); if (filters.status) params.set("status", filters.status); if (filters.eventType) params.set("event_type", filters.eventType); let cancelled = false; let busy = false; const load = async () => { if (cancelled || busy) return; busy = true; try { const response = await fetch(`/api/analytics/communication?${params.toString()}`, { cache: "no-store" }); const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar o dashboard."); if (!cancelled) { setPayload(body as Data); setError(""); } } catch (reason) { if (!cancelled) setError(reason instanceof Error ? reason.message : "Não foi possível actualizar o dashboard."); } finally { busy = false; } }; void load(); const timer = window.setInterval(() => void load(), 10_000); const refresh = () => void load(); window.addEventListener("focus", refresh); return () => { cancelled = true; window.clearInterval(timer); window.removeEventListener("focus", refresh); }; }, [mode, filters.period, filters.from, filters.to, filters.platform, filters.channel, filters.status, filters.eventType]);
  const data = payload?.data;
  const kpis: KPIResult[] = mode === "marketing" ? [
    { id: "campaigns", label: "Campanhas ativas", value: numberValue(data?.campaignsActive), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "marketing_campaigns · estado" },
    { id: "leads", label: "Leads captados", value: numberValue(data?.leadsCaptured), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "marketing_leads · período" },
    { id: "converted", label: "Leads convertidos", value: numberValue(data?.leadsConverted), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "marketing_leads · estado" },
    { id: "conversion", label: "Taxa de conversão", value: numberValue(data?.conversionRate), unit: "%", sourceStatus: data?.conversionRate == null ? "unavailable" : "fresh", source: "convertidos ÷ leads" },
    { id: "investment", label: "Investimento", value: numberValue(data?.investment), unit: "MZN", sourceStatus: data ? "fresh" : "unavailable", source: "marketing_metrics · spend" },
    { id: "cpl", label: "Custo por lead", value: numberValue(data?.costPerLead), unit: "MZN", sourceStatus: data?.costPerLead == null ? "unavailable" : "fresh", source: "spend ÷ leads" },
  ] : mode === "inbox" ? [
    { id: "received", label: "Mensagens recebidas", value: numberValue(data?.messagesReceived), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_messages" },
    { id: "sent", label: "Mensagens enviadas", value: numberValue(data?.messagesSent), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_replies" },
    { id: "open", label: "Conversas abertas", value: numberValue(data?.conversationsOpen), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_messages · estado" },
    { id: "pending", label: "Conversas pendentes", value: numberValue(data?.conversationsPending), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "estado" },
    { id: "assigned", label: "Conversas atribuídas", value: numberValue(data?.conversationsAssigned), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "assigned_to" },
    { id: "unanswered", label: "Sem resposta", value: numberValue(data?.conversationsWithoutResponse), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "mensagens sem reply" },
  ] : [
    { id: "received", label: "Mensagens recebidas", value: numberValue(data?.messagesReceived), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_messages" },
    { id: "sent", label: "Mensagens enviadas", value: numberValue(data?.messagesSent), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_replies" },
    { id: "open", label: "Conversas abertas", value: numberValue(data?.conversationsOpen), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "inbox_messages · estado" },
    { id: "pending", label: "Conversas pendentes", value: numberValue(data?.conversationsPending), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "estado" },
    { id: "assigned", label: "Conversas atribuídas", value: numberValue(data?.conversationsAssigned), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "assigned_to" },
    { id: "unanswered", label: "Sem resposta", value: numberValue(data?.conversationsWithoutResponse), unit: "count", sourceStatus: data ? "fresh" : "unavailable", source: "mensagens sem reply" },
  ];
  const firstBreakdown = mode === "marketing" ? data?.byStatus : data?.byChannel; const secondBreakdown = mode === "marketing" ? data?.byChannel : data?.byStatus;
  const options = (values: string[] | undefined, emptyLabel: string) => <><option value="">{emptyLabel}</option>{(values || []).map(value => <option value={value} key={value}>{filterLabel(value)}</option>)}</>;
  return <section className="analyticsDashboardShell communicationAnalyticsDashboard"><DashboardHeader title={mode === "marketing" ? "Analytics de Marketing" : "Analytics da Caixa de Entrada"} description={mode === "marketing" ? "Campanhas, leads e investimento com origem verificável." : "Volume e estados da caixa de entrada sem expor conteúdo privado."} updatedAt={payload?.range ? `${payload.range.from} → ${payload.range.to}` : undefined} /><details className="analyticsFilterDisclosure"><summary>Filtros</summary><DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} /><div className="analyticsFilters" aria-label="Filtros de comunicação"><label><span>Estado</span><select value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })}>{options(data?.filters?.statuses, "Todos os estados")}</select></label><label><span>Canal</span><select value={filters.channel || ""} onChange={event => setFilters({ ...filters, channel: event.target.value || undefined })}>{options(data?.filters?.channels, "Todos os canais")}</select></label><label><span>Tipo de evento</span><select value={filters.eventType || ""} onChange={event => setFilters({ ...filters, eventType: event.target.value || undefined })}>{options(data?.filters?.eventTypes, "Todos os tipos")}</select></label></div></details>{error ? <EmptyState title="Dashboard indisponível" description={error} /> : <><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title={mode === "marketing" ? "Campanhas por estado" : "Volume por canal"} description="Agregação da fonte autorizada."><AnalyticsBarChart data={firstBreakdown} label={mode === "marketing" ? "Campanhas" : "Mensagens"} /></ChartContainer><ChartContainer title={mode === "marketing" ? "Conversões por canal" : "Conversas por estado"} description="Sem conteúdo privado ou credenciais."><AnalyticsDataTable rows={rows(secondBreakdown)} columns={[{ key: "label", label: "Categoria" }, { key: "total", label: "Total" }]} empty="Sem dados verificáveis." /></ChartContainer></div><ChartContainer title="Evolução diária" description="Série real da fonte autorizada; não são criados pontos fictícios."><AnalyticsLineChart data={(data?.series || []).map(point => ({ date: point.date, value: point.value }))} label={mode === "marketing" ? "Leads" : "Mensagens"} /></ChartContainer><div className="analyticsDataNote">{payload?.limitations?.join(" ")}</div></>}</section>;
}
