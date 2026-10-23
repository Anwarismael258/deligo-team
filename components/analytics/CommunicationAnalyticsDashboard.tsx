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
type Data = { range?: { from: string; to: string }; data?: Record<string, unknown> & { byStatus?: Breakdown; byChannel?: Breakdown; byPlatform?: Breakdown; byType?: Breakdown; series?: Array<{ date: string; value: number }>; filters?: { platforms?: string[]; channels?: string[] } }; limitations?: string[] };
const numberValue = (value: unknown) => typeof value === "number" && Number.isFinite(value) ? value : null;
const rows = (items?: Breakdown) => (items || []).map(item => ({ id: item.label, label: item.label, total: item.value }));

export function CommunicationAnalyticsDashboard({ mode }: { mode: Mode }) {
  const [filters, setFilters] = useState<AnalyticsFilters>({ period: "last_30_days", timezone: "Africa/Maputo" });
  const [payload, setPayload] = useState<Data | null>(null); const [error, setError] = useState("");
  useEffect(() => { const params = new URLSearchParams({ mode, period: filters.period }); if (filters.from) params.set("from", filters.from); if (filters.to) params.set("to", filters.to); if (filters.platform) params.set("platform", filters.platform); if (filters.channel) params.set("channel", filters.channel); if (filters.status) params.set("status", filters.status); if (filters.eventType) params.set("event_type", filters.eventType); let cancelled = false; fetch(`/api/analytics/communication?${params.toString()}`, { cache: "no-store" }).then(async response => { const body = await response.json(); if (!response.ok) throw new Error(body.error || "Não foi possível carregar o dashboard."); return body as Data; }).then(next => { if (!cancelled) { setPayload(next); setError(""); } }).catch(reason => { if (!cancelled) { setPayload(null); setError(reason instanceof Error ? reason.message : "Dashboard indisponível."); } }); return () => { cancelled = true; }; }, [mode, filters.period, filters.from, filters.to, filters.platform, filters.channel, filters.status, filters.eventType]);
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
  return <section className="analyticsDashboardShell communicationAnalyticsDashboard"><DashboardHeader title={mode === "marketing" ? "Analytics de Marketing" : "Analytics da Caixa de Entrada"} description={mode === "marketing" ? "Campanhas, leads e investimento com origem verificável." : "Volume e estados da caixa de entrada sem expor conteúdo privado."} updatedAt={payload?.range ? `${payload.range.from} → ${payload.range.to}` : undefined} /><DashboardFilters value={filters} onChange={setFilters} platforms={data?.filters?.platforms || []} /><div className="analyticsFilters" aria-label="Filtros de comunicação"><label><span>Estado</span><input value={filters.status || ""} onChange={event => setFilters({ ...filters, status: event.target.value || undefined })} placeholder="Todos os estados" /></label><label><span>Canal</span><input value={filters.channel || ""} onChange={event => setFilters({ ...filters, channel: event.target.value || undefined })} placeholder="Todos os canais" /></label><label><span>Tipo de evento</span><input value={filters.eventType || ""} onChange={event => setFilters({ ...filters, eventType: event.target.value || undefined })} placeholder="Todos os tipos" /></label></div>{error ? <EmptyState title="Dashboard indisponível" description={error} /> : <><KPIGrid items={kpis} /><div className="analyticsExecutiveGrid"><ChartContainer title={mode === "marketing" ? "Campanhas por estado" : "Volume por canal"} description="Agregação da fonte autorizada."><AnalyticsBarChart data={firstBreakdown} label={mode === "marketing" ? "Campanhas" : "Mensagens"} /></ChartContainer><ChartContainer title={mode === "marketing" ? "Conversões por canal" : "Conversas por estado"} description="Sem conteúdo privado ou credenciais."><AnalyticsDataTable rows={rows(secondBreakdown)} columns={[{ key: "label", label: "Categoria" }, { key: "total", label: "Total" }]} empty="Sem dados verificáveis." /></ChartContainer></div><ChartContainer title="Evolução diária" description="Série real da fonte autorizada; não são criados pontos fictícios."><AnalyticsLineChart data={(data?.series || []).map(point => ({ date: point.date, value: point.value }))} label={mode === "marketing" ? "Leads" : "Mensagens"} /></ChartContainer><div className="analyticsDataNote">{payload?.limitations?.join(" ")}</div></>}</section>;
}
