"use client";

import { useEffect, useMemo, useState } from "react";
import { CheckCircle2, Headphones, MapPinned, Megaphone, RefreshCw } from "lucide-react";

type ModuleKey = "marketing" | "support" | "field";
type Row = Record<string, unknown>;
type Payload = { collections: Record<string, Row[]>; checkedAt: string; permissions?: { canDecideKyc?: boolean } };
const config = {
  marketing: { title: "Centro de Marketing", icon: Megaphone, sets: { requests: "Pedidos", campaigns: "Campanhas", events: "Eventos" } },
  support: { title: "Centro de Suporte", icon: Headphones, sets: { tickets: "Tickets", messages: "Conversas", disputes: "Disputas" } },
  field: { title: "Operações Field", icon: MapPinned, sets: { verifications: "Todos os KYC", deligoKyc: "DeliGo", sarcaDrivers: "SARCA", comunhaoChurches: "Comunhão", taomozSellers: "TaoMoz", restaurants: "Restaurantes", couriers: "Estafetas", notes: "Notas internas" } },
} as const;
const pick = (row: Row, keys: string[]) => keys.map(key => row[key]).find(item => item !== null && item !== undefined && String(item).trim())?.toString() || "—";

export default function OperationalModule({ module }: { module: ModuleKey }) {
  const [data, setData] = useState<Payload | null>(null);
  const [selected, setSelected] = useState("");
  const [query, setQuery] = useState("");
  const [notice, setNotice] = useState("A ligar ao backend…");
  const meta = config[module], Icon = meta.icon;
  const load = async () => {
    setNotice("A sincronizar…");
    const response = await fetch(`/api/operations?module=${module}`, { cache: "no-store" });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Falha ao carregar."); return; }
    setData(result); setSelected(current => current || Object.keys(result.collections)[0]); setNotice("");
  };
  useEffect(() => { void load(); }, [module]);
  const rows = useMemo(() => (data?.collections[selected] || []).filter(row => JSON.stringify(row).toLowerCase().includes(query.toLowerCase())), [data, selected, query]);
  const all = data ? Object.values(data.collections).flat() : [];
  const pending = all.filter(row => ["open", "pending", "submitted", "in_progress", "draft"].includes(pick(row, ["status", "kyc_status"]))).length;
  const update = async (id: string, action: string) => {
    setNotice("A actualizar…");
    const response = await fetch("/api/operations", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module, entity: selected, id, action }) });
    const result = await response.json(); if (!response.ok) { setNotice(result.error); return; } await load();
  };
  const decideKyc = async (row: Row, action: string) => {
    const reason = action === "approve" ? "" : window.prompt(action === "reject" ? "Motivo da rejeição" : "Correcções necessárias") || "";
    if (action !== "approve" && reason.trim().length < 6) { setNotice("Indique um motivo com pelo menos 6 caracteres."); return; }
    setNotice("A registar decisão KYC…");
    const response = await fetch("/api/operations", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module: "field", entity: "kyc", id: String(row.id || row.user_id), platform: String(row._platform || ""), action, reason }) });
    const result = await response.json(); if (!response.ok) { setNotice(result.error); return; } await load();
  };
  const createRecord = async (entity: string, id?: string) => {
    const promptLabel = entity === "campaign" ? "Título da nova campanha" : entity === "message" ? "Responder ao ticket" : "Nota interna Field";
    const text = window.prompt(promptLabel) || ""; if (text.trim().length < 3) return;
    setNotice("A guardar…");
    const response = await fetch("/api/operations", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module, entity, id, ...(entity === "campaign" ? { title: text } : { text }) }) });
    const result = await response.json(); if (!response.ok) { setNotice(result.error); return; } await load();
  };

  return <section className="operationalModule">
    <div className="operationalHero"><div className="operationalIcon"><Icon /></div><div><span>DADOS REAIS · DELIGO STAGING</span><h2>{meta.title}</h2><p>Fluxos administrativos adaptados ao HQ central.</p></div>{module === "marketing" && <button onClick={() => createRecord("campaign")}>Nova campanha</button>}<button onClick={load}><RefreshCw /> Actualizar</button></div>
    <div className="operationalStats">{[["Total carregado", all.length], ["Pendentes / activos", pending], ["Colecções ligadas", data ? Object.keys(data.collections).length : 0], ["Última sincronização", data ? new Date(data.checkedAt).toLocaleTimeString("pt-MZ", { hour: "2-digit", minute: "2-digit" }) : "—"]].map(([label, value]) => <div key={label}><span>{label}</span><strong>{value}</strong></div>)}</div>
    {module === "field" && <div className="approvalPolicy"><strong>Sequência de aprovação</strong><span>Submissão → verificação Field → decisão de Operações/Supervisor → activação</span><b>Super Admin: excepções</b></div>}
    <div className="operationalToolbar"><div>{Object.entries(meta.sets).map(([key, label]) => <button key={key} className={selected === key ? "active" : ""} onClick={() => setSelected(key)}>{label}<b>{data?.collections[key]?.length || 0}</b></button>)}</div><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar nome, telefone, estado…" /></div>
    {notice && <div className="operationalNotice">{notice}</div>}
    <div className="operationalTable"><div className="operationalRow operationalHeader"><span>Nome / referência</span><span>Plataforma / detalhe</span><span>Estado</span><span>Actualização</span><span>Acções</span></div>
      {rows.map((row, index) => { const date = pick(row, ["updated_at", "created_at", "event_date"]); const isKyc = module === "field" && !["restaurants", "couriers", "notes"].includes(selected); return <div className="operationalRow" key={String(row.id || row.user_id || index)}><div><strong>{pick(row, ["customer_name", "sender_name", "full_name", "church_name", "store_name", "event_name", "campaign_title", "title", "name", "reason", "text", "description", "user_id"])}</strong><small>{pick(row, ["_subject_type", "id", "user_id"])}</small></div><span>{pick(row, ["_platform", "customer_phone", "phone", "request_type", "city", "location", "role", "objective"])}</span><b className="operationalStatus">{pick(row, ["status", "kyc_status", "is_active"])}</b><span>{date !== "—" ? new Date(date).toLocaleDateString("pt-MZ") : "—"}</span><div className="rowActions">{module === "support" && selected === "tickets" && <><button onClick={() => createRecord("message", String(row.id))}>Responder</button><button onClick={() => update(String(row.id), "in_progress")}>Assumir</button><button onClick={() => update(String(row.id), "resolved")}><CheckCircle2 /> Resolver</button></>}{isKyc && <button onClick={() => createRecord("note", String(row.id || row.user_id))}>Nota</button>}{isKyc && data?.permissions?.canDecideKyc && <><button onClick={() => decideKyc(row, "correction")}>Corrigir</button><button onClick={() => decideKyc(row, "reject")}>Rejeitar</button><button onClick={() => decideKyc(row, "approve")}><CheckCircle2 /> Aprovar</button></>}</div></div>; })}
      {!rows.length && !notice && <div className="peopleEmpty">Nenhum registo encontrado.</div>}
    </div>
  </section>;
}
