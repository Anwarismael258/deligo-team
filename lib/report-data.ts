import { hqRest, stagingRest } from "@/lib/hq-server";

export type ReportType = "financial" | "marketing" | "field" | "support";
export type ReportFilters = {
  period?: string | null;
  from?: string | null;
  to?: string | null;
  platform?: string | null;
  department?: string | null;
  responsible?: string | null;
  status?: string | null;
  allowedPlatforms?: string[] | null;
};
type Row = Record<string, unknown>;
type SourceState = "fresh" | "empty" | "unavailable";
export type ReportRecord = {
  id: string;
  date: string | null;
  reference: string | null;
  platform: string | null;
  category: string | null;
  value: number | null;
  currency: string | null;
  status: string | null;
  responsible: string | null;
  client: string | null;
  subject: string | null;
  metadata: Row;
};

const text = (row: Row, keys: string[]) => {
  for (const key of keys) {
    const value = row[key];
    if (value !== null && value !== undefined && String(value).trim()) return String(value);
  }
  return null;
};
const number = (row: Row, keys: string[]) => {
  const value = keys.map(key => row[key]).find(item => item !== null && item !== undefined && item !== "");
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};
const date = (row: Row, keys: string[]) => text(row, keys);
const isoDay = (value: string | null) => value ? value.slice(0, 10) : null;
const dateForType = (type: ReportType) => type === "financial" ? ["occurred_at", "created_at"] : type === "field" ? ["planned_at", "created_at"] : ["created_at", "opened_at", "updated_at"];
const periodDates = (filters: ReportFilters) => {
  if (filters.from && filters.to) return { from: filters.from.slice(0, 10), to: filters.to.slice(0, 10) };
  const days = filters.period === "today" ? 1 : filters.period === "last_7_days" ? 7 : filters.period === "last_90_days" ? 90 : 30;
  const end = new Date();
  const start = new Date(end.getTime() - (days - 1) * 86_400_000);
  return { from: start.toISOString().slice(0, 10), to: end.toISOString().slice(0, 10) };
};
const platformMatches = (record: ReportRecord, selected: string | null | undefined) => !selected || [record.platform, String(record.metadata.platform_id || ""), String(record.metadata.platform_slug || "")].some(value => value?.toLowerCase() === selected.toLowerCase());
const normalize = (type: ReportType, row: Row): ReportRecord => {
  const dateKeys = dateForType(type);
  return {
    id: text(row, ["id", "uuid", "reference", "external_reference"]) || "sem-id",
    date: date(row, dateKeys),
    reference: text(row, ["reference", "external_reference", "ticket_number", "code"]),
    platform: text(row, ["platform_name", "platform_slug", "platform"]),
    category: text(row, ["category", "type", "transaction_type", "department", "request_type"]),
    value: number(row, ["amount", "value", "budget_amount", "budget"]),
    currency: text(row, ["currency", "currency_code"]),
    status: text(row, ["status", "state"]),
    responsible: text(row, ["responsible_name", "agent_name", "assigned_to_name", "assigned_to", "created_by"]),
    client: text(row, ["customer_name", "client_name", "customer", "requester_name"]),
    subject: text(row, ["subject", "title", "name", "description"]),
    metadata: row,
  };
};
async function sourceRows(type: ReportType): Promise<{ rows: Row[]; source: string; state: SourceState; error?: string }> {
  const config: Record<ReportType, { source: string; read: () => Promise<unknown> }> = {
    financial: { source: "hq.financial_transactions", read: () => hqRest("financial_transactions?select=*&order=occurred_at.desc&limit=5000") },
    marketing: { source: "public.marketing_campaigns", read: () => stagingRest("marketing_campaigns?select=*&order=created_at.desc&limit=5000") },
    field: { source: "hq.field_visits", read: () => hqRest("field_visits?select=*&order=planned_at.desc&limit=5000") },
    support: { source: "public.support_tickets", read: () => stagingRest("support_tickets?select=*&order=opened_at.desc&limit=5000") },
  };
  try {
    const result = await config[type].read();
    const rows = Array.isArray(result) ? result as Row[] : [];
    return { rows, source: config[type].source, state: rows.length ? "fresh" : "empty" };
  } catch (error) {
    return { rows: [], source: config[type].source, state: "unavailable", error: error instanceof Error ? error.message.slice(0, 240) : "Fonte indisponível" };
  }
}
export async function getReportData(type: ReportType, filters: ReportFilters = {}) {
  const source = await sourceRows(type);
  const range = periodDates(filters);
  const records = source.rows.map(row => normalize(type, row)).filter(record => {
    const day = isoDay(record.date);
    const inPeriod = !day || (day >= range.from && day <= range.to);
    const status = !filters.status || String(record.status || "").toLowerCase() === filters.status.toLowerCase();
    const department = !filters.department || [record.category, String(record.metadata.department_id || ""), String(record.metadata.department || "")].some(value => value?.toLowerCase() === filters.department?.toLowerCase());
    const responsible = !filters.responsible || String(record.responsible || "").toLowerCase().includes(filters.responsible.toLowerCase());
    const platformAllowed = filters.allowedPlatforms === undefined || filters.allowedPlatforms === null ? true : filters.allowedPlatforms.length > 0 && filters.allowedPlatforms.some(allowed => [record.platform, String(record.metadata.platform_id || ""), String(record.metadata.platform_slug || "")].some(value => value?.toLowerCase() === allowed.toLowerCase()));
    return inPeriod && status && department && responsible && platformMatches(record, filters.platform) && platformAllowed;
  });
  const unavailable = source.state === "unavailable";
  const statuses = new Map<string, number>();
  records.forEach(record => { const key = record.status || "Não indicado"; statuses.set(key, (statuses.get(key) || 0) + 1); });
  const values = records.map(record => record.value).filter((value): value is number => value !== null);
  const revenue = type === "financial" ? records.filter(record => /revenue|income|commission|fee|receita|comiss/i.test(`${record.category} ${record.status}`)).reduce((sum, record) => sum + (record.value || 0), 0) : null;
  const expenses = type === "financial" ? records.filter(record => /expense|debit|despesa|pagamento/i.test(`${record.category} ${record.status}`)).reduce((sum, record) => sum + (record.value || 0), 0) : null;
  const summary = unavailable ? null : {
    total: records.length,
    value: values.length ? values.reduce((sum, value) => sum + value, 0) : null,
    revenue,
    expenses,
    balance: revenue !== null && expenses !== null ? revenue - expenses : null,
    pending: records.filter(record => /pending|open|in_progress|submitted|review|pendente|aberto/i.test(record.status || "")).length,
    statuses: [...statuses.entries()].map(([label, value]) => ({ label, value })),
    metricsUnavailable: type === "support" ? ["Tempo de primeira resposta", "Tempo de resolução"] : type === "field" ? ["KYC aprovado", "Parceiros integrados"] : type === "marketing" ? ["Alcance", "Conversões", "Retorno"] : [],
  };
  return { type, range, source: source.source, sourceState: source.state, sourceError: source.error || null, summary, records, limitations: summary?.metricsUnavailable || (unavailable ? ["A fonte autorizada não respondeu."] : []) };
}
