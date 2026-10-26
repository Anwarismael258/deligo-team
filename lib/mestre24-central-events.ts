import { hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { canonicalCorporateRole } from "@/lib/corporate-roles";

type Row = Record<string, unknown>;

const inboxRoles = new Set([
  "SUPER_ADMIN",
  "FINANCE",
  "SUPERVISOR",
  "CUSTOMER_SUPPORT",
  "MARKETING",
]);

function headers(serviceKey: string, profile: string) {
  const value: Record<string, string> = {
    apikey: serviceKey,
    "Accept-Profile": profile,
    "Content-Profile": profile,
    "Content-Type": "application/json",
    Prefer: "return=representation",
  };
  if (!serviceKey.startsWith("sb_secret_")) value.Authorization = `Bearer ${serviceKey}`;
  return value;
}

async function rest(serviceKey: string, profile: string, path: string, init: RequestInit = {}) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: { ...headers(serviceKey, profile), ...(init.headers || {}) },
    cache: "no-store",
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(await response.text());
  return response.status === 204 ? null : response.json();
}

function eventText(event: Row) {
  const type = String(event.event_type || "");
  const payload = event.payload && typeof event.payload === "object" ? event.payload as Row : {};
  const current = payload.new && typeof payload.new === "object" ? payload.new as Row : {};
  const status = String(current.status || "").toLowerCase();
  const reference = String(current.id || event.entity_id || "").slice(0, 8);
  const source = `${type} ${String(event.entity_type || "")} ${JSON.stringify(current)}`.toLowerCase();
  const value = (...keys: string[]) => {
    for (const key of keys) {
      const found = current[key] ?? payload[key];
      if (found !== undefined && found !== null && String(found).trim()) return String(found).trim();
    }
    return "";
  };

  if (/(service[_ ]request|booking|appointment|professional[_ ]request)/.test(source)) {
    const professional = value("professional_name", "provider_name", "professional", "provider");
    const customer = value("customer_name", "client_name", "customer", "client");
    const professionalPhone = value("professional_phone", "provider_phone", "professional_contact", "provider_contact");
    const customerPhone = value("customer_phone", "client_phone", "customer_contact", "client_contact");
    const service = value("service_name", "service_title", "title", "description");
    const date = value("scheduled_at", "appointment_at", "requested_for", "date");
    const details = [
      professional ? `Profissional: ${professional}` : "",
      customer ? `Cliente: ${customer}` : "",
      professionalPhone ? `Contacto profissional: ${professionalPhone}` : "",
      customerPhone ? `Contacto cliente: ${customerPhone}` : "",
      service ? `Serviço: ${service}` : "",
      date ? `Data: ${date}` : "",
      reference ? `#${reference}` : "",
    ].filter(Boolean);
    return {
      title: professional ? `Pedido para ${professional}` : "Novo pedido Mestre24",
      body: details.join(" · ") || "A Central recebeu um pedido de serviço Mestre24.",
      target: "/plataformas?platform=mestre24&tab=pedidos",
      audience: "operations",
    };
  }

  if (type.includes("kyc")) {
    return {
      title: status ? `KYC Mestre24 actualizado: ${status}` : "Novo KYC Mestre24 recebido",
      body: `Há uma submissão de documentos do Mestre24 para revisão${reference ? ` · ${reference}` : ""}.`,
      target: "/plataformas/mestre24?tab=kyc",
      audience: "operations",
    };
  }
  if (type.includes("subscription")) {
    return {
      title: status ? `Subscrição Mestre24: ${status}` : "Nova subscrição Mestre24",
      body: `A Central recebeu uma atualização de subscrição${reference ? ` · ${reference}` : ""}.`,
      target: "/plataformas/mestre24?tab=subscricoes",
      audience: "finance",
    };
  }
  return {
    title: type.includes("message") ? "Nova mensagem de suporte Mestre24" : "Novo atendimento Mestre24",
    body: "A Central recebeu uma nova mensagem ou atualização de suporte.",
    target: "/apoio-cliente?platform=mestre24",
    audience: "support",
  };
}

function recipients(employees: Row[], audience: string) {
  return employees.filter((employee) => {
    const roleLinks = Array.isArray(employee.employee_roles) ? employee.employee_roles as Row[] : [];
    const linkedRole = roleLinks.map(link => {
      const roles = link.roles && typeof link.roles === "object" ? link.roles as Row : {};
      return String(roles.code || link.role_code || "");
    }).find(Boolean);
    const role = canonicalCorporateRole(String(employee.role || linkedRole || ""));
    if (!inboxRoles.has(role)) return false;
    if (role === "SUPER_ADMIN" || role === "SUPERVISOR") return true;
    if (audience === "support") return ["CUSTOMER_SUPPORT", "SUPERVISOR", "MARKETING"].includes(role);
    if (audience === "finance") return ["FINANCE", "SUPERVISOR"].includes(role);
    return ["SUPERVISOR", "OPERATIONS", "FINANCE"].includes(role);
  });
}

/**
 * Moves the Mestre24 outbox into the existing HQ inbox. The browser only sees
 * hq.notifications; the service key stays on the Central server.
 */
export async function ingestMestre24CentralEvents() {
  const serviceKey = hqServiceKey();
  if (!serviceKey) return { inserted: 0, events: 0 };

  const [events, employees, existing] = await Promise.all([
    rest(serviceKey, "mestre24", "central_events?app_slug=eq.mestre24&select=id,event_type,entity_type,entity_id,payload,created_at&order=created_at.desc&limit=100") as Promise<Row[]>,
    rest(serviceKey, "hq", "employees?status=eq.active&select=id,employee_roles:employee_roles!employee_roles_employee_id_fkey(roles(code))&limit=1000") as Promise<Row[]>,
    rest(serviceKey, "hq", "notifications?type=eq.mestre24_central_event&select=target_url&order=created_at.desc&limit=5000") as Promise<Row[]>,
  ]);
  const known = new Set((existing || []).map((row) => String(row.target_url || "").match(/central_event_id=([^&]+)/)?.[1]).filter(Boolean));
  const activeEmployees = Array.isArray(employees) ? employees : [];
  const rows: Row[] = [];
  for (const event of Array.isArray(events) ? events : []) {
    const id = String(event.id || "");
    if (!id || known.has(id)) continue;
    const text = eventText(event);
    const targets = recipients(activeEmployees, text.audience);
    for (const employee of targets) {
      rows.push({
        employee_id: employee.id,
        type: "mestre24_central_event",
        source_type: "mestre24_central_event",
        source_id: id,
        title: text.title,
        body: text.body,
        platform_id: null,
        target_url: `${text.target}&central_event_id=${encodeURIComponent(id)}`,
      });
    }
    known.add(id);
  }
  if (rows.length) await rest(serviceKey, "hq", "notifications", { method: "POST", body: JSON.stringify(rows) });
  return { inserted: rows.length, events: Array.isArray(events) ? events.length : 0 };
}
