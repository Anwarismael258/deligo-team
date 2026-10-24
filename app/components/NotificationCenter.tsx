"use client";

import { useEffect, useMemo, useState } from "react";

type Row = Record<string, unknown>;
const text = (value: unknown, fallback = "") => String(value ?? fallback);
const platformOf = (item: Row) => text(item.platform_name || item.platform || item.source_platform, "Central");
const priorityOf = (item: Row) => text(item.priority, "normal").toLowerCase();
const destinationOf = (item: Row) => {
  const direct = text(item.target_url).trim();
  if (direct.startsWith("/") && direct !== "/" && !direct.startsWith("//")) return direct;
  const source = `${text(item.source_type)} ${text(item.type)} ${text(item.title)} ${text(item.body)}`.toLowerCase();
  if (["order", "delivery", "ride", "trip", "journey", "travel"].some(value => source.includes(value))) return "/mapa-operacional";
  if (["dispute", "complaint", "support", "ticket", "whatsapp", "message"].some(value => source.includes(value))) return "/apoio-cliente";
  if (["kyc", "field", "courier", "restaurant"].some(value => source.includes(value))) return "/field";
  if (["service_request", "service request", "booking", "appointment", "professional_request"].some(value => source.includes(value))) return "/plataformas?platform=mestre24&tab=pedidos";
  if (source.includes("task") || source.includes("project")) return "/projectos-tarefas";
  if (["finance", "withdraw", "payment"].some(value => source.includes(value))) return "/financas";
  if (source.includes("loan") || source.includes("credit")) return "/microcredito";
  if (source.includes("user") || source.includes("profile")) return "/utilizadores";
  return "/notificacoes";
};
const actionLabelOf = (item: Row) => {
  const source = `${text(item.source_type)} ${text(item.type)} ${text(item.title)} ${text(item.body)}`.toLowerCase();
  if (source.includes("kyc") || source.includes("field")) return "Rever KYC";
  if (["support", "ticket", "message", "whatsapp", "dispute"].some(value => source.includes(value))) return "Abrir mensagem";
  if (["order", "delivery", "ride", "trip", "journey", "travel"].some(value => source.includes(value))) return "Acompanhar rota";
  if (["service_request", "service request", "booking", "appointment", "professional_request"].some(value => source.includes(value))) return "Abrir pedido";
  return "Abrir origem";
};
const summaryOf = (item: Row) => {
  const source = `${text(item.source_type)} ${text(item.type)}`.toLowerCase();
  const title = text(item.title, "Notificação").trim();
  const body = text(item.body).trim();
  const platform = platformOf(item);
  const reference = text(item.source_id).trim();
  if (source.includes("kyc") || source.includes("field")) return `Novo KYC para revisão · ${platform}${reference ? ` · #${reference.slice(0, 12)}` : ""}`;
  if (["support", "ticket", "message", "whatsapp"].some(value => source.includes(value))) return `${title} · ${platform}${body ? ` · ${body}` : ""}`;
  if (["platform_event", "order", "delivery", "ride", "trip"].some(value => source.includes(value))) return `${title} · ${platform}${reference ? ` · #${reference.slice(0, 12)}` : body ? ` · ${body}` : ""}`;
  return body || `${title}${reference ? ` · #${reference.slice(0, 12)}` : ""}`;
};

export function NotificationCenter() {
  const [data, setData] = useState<Row[]>([]);
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(true);
  const load = async () => { try { const response = await fetch("/api/notifications", { cache: "no-store" }); const result = await response.json(); if (!response.ok) throw new Error(result.error || "Não foi possível actualizar as notificações."); setData(Array.isArray(result.notifications) ? result.notifications : []); setNotice(""); } catch (error) { setNotice(error instanceof Error ? error.message : "Não foi possível actualizar as notificações."); } finally { setLoading(false); } };
  useEffect(() => { void load(); const timer = window.setInterval(() => void load(), 10000); return () => window.clearInterval(timer); }, []);
  const mark = async (id?: string) => { const response = await fetch("/api/notifications", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(id ? { id } : { all: true }) }); if (!response.ok) { setNotice("Não foi possível actualizar o estado da notificação."); return; } await load(); };
  const groups = useMemo(() => { const grouped = new Map<string, Row[]>(); [...data].sort((a, b) => Date.parse(text(b.created_at)) - Date.parse(text(a.created_at))).forEach(item => { const key = platformOf(item); grouped.set(key, [...(grouped.get(key) || []), item]); }); return [...grouped.entries()].sort(([a], [b]) => a === "Central" ? 1 : b === "Central" ? -1 : a.localeCompare(b, "pt")); }, [data]);
  const unread = data.filter(item => !item.read_at).length;
  const open = (item: Row) => { if (!item.read_at) void mark(text(item.id)); window.location.assign(destinationOf(item)); };
  return <section className="notificationCenterWorkspace"><div className="notificationCenterHead"><div><span>INBOX INTERNA</span><h2>Notificações</h2></div><button className="notificationMarkAll" onClick={() => void mark()} disabled={!unread}>Ler tudo</button></div><div className="notificationSummary"><article><span>Total</span><strong>{data.length}</strong></article><article className={unread ? "hasUnread" : ""}><span>Não lidas</span><strong>{unread}</strong></article><article><span>Plataformas</span><strong>{groups.length}</strong></article></div>{notice && <div className="operationalNotice">{notice}</div>}{loading ? <div className="notificationEmpty">A carregar…</div> : !data.length ? <div className="notificationEmpty">Sem notificações.</div> : <div className="notificationGroups">{groups.map(([platform, items]) => <section className="notificationGroup" key={platform}><header><div><span>PLATAFORMA</span><h3>{platform}</h3></div><b>{items.filter(item => !item.read_at).length || ""}</b></header><div className="notificationList">{items.map(item => { const isUnread = !item.read_at; const priority = priorityOf(item); return <article className={`notificationItem ${isUnread ? "isUnread" : ""}`} key={text(item.id)} onClick={() => open(item)} role="button" tabIndex={0} onKeyDown={event => { if (event.key === "Enter" || event.key === " ") open(item); }}><i className={`notificationDot priority-${priority}`} aria-hidden="true" /><div className="notificationItemBody"><div className="notificationItemTitle"><strong>{summaryOf(item)}</strong><span className={`notificationPriority priority-${priority}`}>{priority}</span></div><small>{new Date(text(item.created_at)).toLocaleString("pt-MZ")}</small></div><div className="notificationItemActions"><button type="button" onClick={event => { event.stopPropagation(); open(item); }}>{actionLabelOf(item)}</button>{isUnread && <button type="button" onClick={event => { event.stopPropagation(); void mark(text(item.id)); }}>Ler</button>}</div></article>; })}</div></section>)}</div>}</section>;
}
