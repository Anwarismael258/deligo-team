"use client";

import { useEffect, useMemo, useState } from "react";

type Row = Record<string, unknown>;
type ViewFilter = "all" | "unread" | "urgent" | "important";
const value = (row: Row, key: string, fallback = "") => String(row[key] ?? fallback);
const sourceText = (row: Row) => value(row, "source_type") + " " + value(row, "type") + " " + value(row, "title") + " " + value(row, "body");
const priority = (row: Row) => value(row, "priority", "normal").toLowerCase();

function platformOf(row: Row) {
  const source = (value(row, "platform_name") + " " + value(row, "platform") + " " + value(row, "platform_slug") + " " + sourceText(row)).toLowerCase();
  if (source.includes("mestre24") || source.includes("mestre 24")) return "Mestre24";
  if (source.includes("sarca")) return "SARCA";
  if (source.includes("comunhao") || source.includes("comunhão") || source.includes("igreja")) return "Comunhão";
  if (source.includes("taomoz") || source.includes("market")) return "DeliGo Market";
  if (source.includes("deligo") || source.includes("eats")) return "DeliGo";
  return "Central";
}

function moduleOf(row: Row) {
  const target = value(row, "target_url").toLowerCase();
  const source = sourceText(row).toLowerCase();
  if (target.startsWith("/inbox-interna")) return "Inbox interna";
  if (target.startsWith("/apoio-cliente") || /support|ticket|complaint|whatsapp|dispute/.test(source)) return "Apoio ao Cliente";
  if (target.startsWith("/caixa-de-entrada") || source.includes("inbox")) return "Caixa de Entrada";
  if (target.startsWith("/field") || /kyc|field/.test(source)) return "Operações de Campo";
  if (target.startsWith("/financas") || /finance|payment|withdrawal/.test(source)) return "Finanças";
  if (target.startsWith("/microcredito") || /loan|credit/.test(source)) return "Triunfal Microcrédito";
  if (target.startsWith("/projectos-tarefas") || /task|project/.test(source)) return "Projectos e Tarefas";
  if (target.startsWith("/relatorios") || source.includes("report")) return "Relatórios";
  if (target.startsWith("/marketing/vagas") || /vacancy|job/.test(source)) return "Vagas";
  if (target.startsWith("/marketing") || /marketing|campaign/.test(source)) return "Marketing";
  if (target.startsWith("/utilizadores") || /user|profile/.test(source)) return "Utilizadores";
  return "Centro de Notificações";
}

function hrefOf(row: Row) {
  const direct = value(row, "target_url").trim();
  if (direct.startsWith("/") && direct !== "/" && !direct.startsWith("//")) return direct;
  const source = sourceText(row).toLowerCase();
  if (/support|ticket|complaint|whatsapp|dispute|message/.test(source)) return "/apoio-cliente";
  if (/kyc|field|courier|restaurant/.test(source)) return "/field";
  if (/order|delivery|ride|trip|journey|travel/.test(source)) return "/mapa-operacional";
  if (/service_request|booking|appointment|professional_request/.test(source)) return "/plataformas?platform=mestre24&tab=pedidos";
  if (/task|project/.test(source)) return "/projectos-tarefas";
  if (/finance|withdraw|payment/.test(source)) return "/financas";
  if (/loan|credit/.test(source)) return "/microcredito";
  return "/notificacoes";
}

function actionOf(row: Row) {
  const source = sourceText(row).toLowerCase();
  if (/kyc|field/.test(source)) return "Rever KYC";
  if (/support|ticket|message|whatsapp|dispute/.test(source)) return "Abrir conversa";
  if (/order|delivery|ride|trip|journey|travel/.test(source)) return "Acompanhar rota";
  if (/service_request|booking|appointment|professional_request/.test(source)) return "Abrir pedido";
  return "Abrir origem";
}

function summaryOf(row: Row) {
  const title = value(row, "title", "Notificação").trim();
  const body = value(row, "body").replace(/\s+/g, " ").trim();
  const source = sourceText(row).toLowerCase();
  const platform = platformOf(row);
  const reference = value(row, "source_id").trim();
  if (/kyc|field/.test(source)) return title + " · " + platform + (reference ? " · #" + reference.slice(0, 12) : "");
  if (/order|delivery|ride|trip|journey|travel/.test(source)) return title + " · " + platform + (reference ? " · #" + reference.slice(0, 12) : "");
  return body ? title + " · " + platform + " · " + body : title + " · " + platform;
}

function uniqueRows(rows: Row[]) {
  const seen = new Set<string>();
  return rows.filter(row => {
    const key = value(row, "id") || value(row, "dedupe_key") || value(row, "source_type") + ":" + value(row, "source_id") + ":" + value(row, "employee_id");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function NotificationCenter() {
  const [data, setData] = useState<Row[]>([]);
  const [view, setView] = useState<ViewFilter>("all");
  const [area, setArea] = useState("Todas as áreas");
  const [platform, setPlatform] = useState("Todas as plataformas");
  const [query, setQuery] = useState("");
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(true);

  const load = async () => {
    try {
      const response = await fetch("/api/notifications", { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Não foi possível actualizar as notificações.");
      setData(uniqueRows(Array.isArray(result.notifications) ? result.notifications : []));
      setNotice("");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Não foi possível actualizar as notificações.");
    } finally { setLoading(false); }
  };
  useEffect(() => { void load(); const timer = window.setInterval(() => void load(), 5000); return () => window.clearInterval(timer); }, []);

  const mark = async (id?: string) => {
    const body = id ? { id } : { all: true };
    setData(rows => id ? rows.map(row => value(row, "id") === id ? { ...row, read_at: new Date().toISOString() } : row) : rows.map(row => ({ ...row, read_at: new Date().toISOString() })));
    const response = await fetch("/api/notifications", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (!response.ok) { setNotice("Não foi possível actualizar o estado da notificação."); await load(); }
  };

  const areas = useMemo(() => ["Todas as áreas"].concat(Array.from(new Set(data.map(moduleOf))).sort((a, b) => a.localeCompare(b, "pt"))), [data]);
  const platforms = ["Todas as plataformas","Central","DeliGo","SARCA","DeliGo Market","Mestre24","Comunhão"];
  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return data.filter(row => {
      if (view === "unread" && value(row, "read_at")) return false;
      if (view === "urgent" && !["urgent", "critical"].includes(priority(row))) return false;
      if (view === "important" && !["high", "urgent", "critical"].includes(priority(row))) return false;
      if (area !== "Todas as áreas" && moduleOf(row) !== area) return false;
      if (platform !== "Todas as plataformas" && platformOf(row) !== platform) return false;
      return !needle || (summaryOf(row) + " " + moduleOf(row) + " " + platformOf(row)).toLowerCase().includes(needle);
    }).sort((a, b) => Date.parse(value(b, "created_at")) - Date.parse(value(a, "created_at")));
  }, [area, data, platform, query, view]);
  const unread = data.filter(row => !value(row, "read_at")).length;
  const open = (row: Row) => { const id = value(row, "id"); if (!value(row, "read_at") && id) void mark(id); window.location.assign(hrefOf(row)); };
  const grouped = useMemo(() => { const groups = new Map<string, Row[]>(); filtered.forEach(row => { const key = platformOf(row); groups.set(key, (groups.get(key) || []).concat(row)); }); return Array.from(groups.entries()); }, [filtered]);

  return <section className="notificationCenterWorkspace">
    <header className="notificationCenterHead"><div className="notificationHeadActions"><span className="notificationLiveState"><i />Tempo real</span><button className="notificationMarkAll" onClick={() => void mark()} disabled={!unread}>✓ Marcar todas como lidas</button></div></header>
    <nav className="notificationFilters" aria-label="Filtros de notificações"><div className="notificationFilterTabs">{([["all", "Todas"], ["unread", "Não lidas"], ["important", "Importantes"], ["urgent", "Urgentes"]] as const).map(([key, label]) => <button key={key} className={view === key ? "active" : ""} onClick={() => setView(key)}>{label}{key === "unread" && unread ? " · " + unread : ""}</button>)}</div><div className="notificationFilterSelects"><select value={area} onChange={event => setArea(event.target.value)} aria-label="Filtrar por área">{areas.map(item => <option key={item}>{item}</option>)}</select><select value={platform} onChange={event => setPlatform(event.target.value)} aria-label="Filtrar por plataforma">{platforms.map(item => <option key={item} value={item}>{item==="DeliGo"?"DeliGo Eats":item}</option>)}</select><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar notificações…" aria-label="Pesquisar notificações" /></div></nav>
    <div className="notificationSummary"><article><span>Total</span><strong>{data.length}</strong></article><article className={unread ? "hasUnread" : ""}><span>Não lidas</span><strong>{unread}</strong></article><article><span>Áreas activas</span><strong>{new Set(data.map(moduleOf)).size}</strong></article></div>
    {notice && <div className="operationalNotice">{notice}</div>}
    {loading ? <div className="notificationEmpty">A carregar notificações reais…</div> : !filtered.length ? <div className="notificationEmpty"><strong>{data.length ? "Nenhuma notificação corresponde aos filtros." : "Sem notificações."}</strong><span>Quando um evento autorizado chegar, aparecerá aqui automaticamente.</span></div> : <div className="notificationGroups">{grouped.map(([name, rows]) => <section className="notificationGroup" key={name}><header><div><span>ORIGEM</span><h3>{name}</h3></div><b>{rows.filter(row => !value(row, "read_at")).length || ""}</b></header><div className="notificationList">{rows.map(row => { const unreadRow = !value(row, "read_at"); const level = priority(row); return <article className={"notificationItem " + (unreadRow ? "isUnread " : "") + "priority-" + level} key={value(row, "id") || value(row, "dedupe_key")} onClick={() => open(row)} role="button" tabIndex={0} onKeyDown={event => { if (event.key === "Enter" || event.key === " ") open(row); }}><span className="notificationIcon" aria-hidden="true">{level === "critical" || level === "urgent" ? "!" : "•"}</span><div className="notificationItemBody"><strong>{summaryOf(row)}</strong><small>{moduleOf(row)} · {new Date(value(row, "created_at")).toLocaleString("pt-MZ", { dateStyle: "short", timeStyle: "short" })}</small></div><div className="notificationItemActions"><button type="button" onClick={event => { event.stopPropagation(); open(row); }}>{actionOf(row)} <span>→</span></button>{unreadRow && <button type="button" className="notificationReadButton" onClick={event => { event.stopPropagation(); void mark(value(row, "id")); }}>Marcar lida</button>}</div></article>; })}</div></section>)}</div>}
  </section>;
}
