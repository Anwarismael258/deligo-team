"use client";

import { submitKycDecision } from "@/lib/kyc-decision-client";
import Image from "next/image";
import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CheckCircle2, Headphones, MapPinned, Megaphone, RefreshCw } from "lucide-react";

type ModuleKey = "marketing" | "support" | "field";
type Row = Record<string, unknown>;
type KycMedia = { key: string; url: string; label: string };
type Payload = { collections: Record<string, Row[]>; checkedAt: string; permissions?: { canDecideKyc?: boolean } };

const config = {
  marketing: { title: "Centro de Marketing", icon: Megaphone, sets: { requests: "Pedidos", campaigns: "Campanhas", events: "Eventos" } },
  support: { title: "Centro de Suporte", icon: Headphones, sets: { tickets: "Tickets", messages: "Conversas", disputes: "Disputas" } },
  field: { title: "Operações Field", icon: MapPinned, sets: { verifications: "Todos os KYC", deligoKyc: "DeliGo", sarcaDrivers: "SARCA", comunhaoChurches: "Comunhão", taomozSellers: "DeliGo Market", restaurants: "Restaurantes", couriers: "Estafetas", notes: "Notas internas" } },
} as const;

const pick = (row: Row, keys: string[]) => keys.map((key) => row[key]).find((item) => item !== null && item !== undefined && String(item).trim())?.toString() || "—";

export default function OperationalModule({ module }: { module: ModuleKey }) {
  const kycInFlight = useRef(new Set<string>());
  const [kycBusy, setKycBusy] = useState<Record<string, boolean>>({});
  const [data, setData] = useState<Payload | null>(null);
  const [selected, setSelected] = useState("");
  const [query, setQuery] = useState("");
  const [notice, setNotice] = useState("A ligar ao backend…");
  const [gallery, setGallery] = useState<{ name: string; media: KycMedia[] } | null>(null);
  const [ticketId, setTicketId] = useState("");
  const [message, setMessage] = useState("");
  const [campaignTitle, setCampaignTitle] = useState("");
  const [showCampaignForm, setShowCampaignForm] = useState(false);
  const meta = config[module];
  const Icon = meta.icon;

  const load = useCallback(async () => {
    setNotice("A sincronizar…");
    const response = await fetch(`/api/operations?module=${module}`, { cache: "no-store" });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Falha ao carregar."); return; }
    setData(result);
    setSelected((current) => current || Object.keys(result.collections)[0]);
    setNotice("");
  }, [module]);

  useEffect(() => { const timer = window.setTimeout(() => { void load(); }, 0); return () => window.clearTimeout(timer); }, [load]);

  const rows = useMemo(() => (data?.collections[selected] || []).filter((row) => JSON.stringify(row).toLowerCase().includes(query.toLowerCase())), [data, selected, query]);
  const all = data ? Object.values(data.collections).flat() : [];
  const ticketMessages = useMemo(() => (data?.collections.messages || []).filter((row) => String(row.ticket_id || "") === ticketId), [data, ticketId]);
  const activeTicket = useMemo(() => (data?.collections.tickets || []).find((row) => String(row.id) === ticketId) || null, [data, ticketId]);

  const decideKyc = async (row: Row, action: "approve" | "reject" | "correction") => {
    const id=String(row.id||row.user_id);
    if(kycInFlight.current.has(id))return;
    const reason=action==="approve"?"":window.prompt(action==="reject"?"Motivo da rejeição":"Correções necessárias");
    if(reason===null)return;
    if(action!=="approve"&&reason.trim().length<6){setNotice("Indique um motivo com pelo menos 6 caracteres.");return;}
    kycInFlight.current.add(id);setKycBusy(current=>({...current,[id]:true}));setNotice("A registar decisão…");
    try{
      const response=await submitKycDecision("/api/operations",{module:"field",entity:"kyc",id,platform:String(row._platform||""),action,reason});
      const status=response.result?.status||(action==="approve"?"approved":action==="reject"?"rejected":"correction_requested");
      setData(current=>current?{...current,collections:Object.fromEntries(Object.entries(current.collections).map(([name,rows])=>[name,rows.map(item=>String(item.id||item.user_id)===id?{...item,status}:item)]))}:current);
      setNotice(response.result?.message||"Decisão registada.");
    }catch(error){setNotice(error instanceof Error?error.message:"Não foi possível concluir a decisão.");}
    finally{kycInFlight.current.delete(id);setKycBusy(current=>({...current,[id]:false}));}
  };

  const setTicketStatus = async (id: string, action: string) => {
    const response = await fetch("/api/operations", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module: "support", entity: "tickets", id, action }) });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Não foi possível atualizar o ticket."); return; }
    await load();
  };

  const sendMessage = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!ticketId || message.trim().length < 2) return;
    setNotice("A enviar mensagem…");
    const response = await fetch("/api/operations", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module: "support", entity: "message", id: ticketId, text: message.trim() }) });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Não foi possível enviar a mensagem."); return; }
    setMessage("");
    await load();
  };

  const createCampaign = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (campaignTitle.trim().length < 3) return;
    setNotice("A criar campanha…");
    const response = await fetch("/api/operations", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module: "marketing", entity: "campaign", title: campaignTitle.trim() }) });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Não foi possível criar a campanha."); return; }
    setCampaignTitle(""); setShowCampaignForm(false); setSelected("campaigns"); await load();
  };

  const updateCampaign = async (id: string, action: "published" | "archived") => {
    if (action === "archived" && !window.confirm("Arquivar esta campanha? Ela deixará de ficar ativa.")) return;
    const response = await fetch("/api/operations", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ module: "marketing", entity: "campaign", id, action }) });
    const result = await response.json();
    if (!response.ok) { setNotice(result.error || "Não foi possível atualizar a campanha."); return; }
    await load();
  };

  return <section className="operationalModule">
    <div className="operationalHero"><div className="operationalIcon"><Icon /></div><div><span>DADOS REAIS · DELIGO STAGING</span><h2>{meta.title}</h2><p>Fluxos administrativos adaptados ao HQ central.</p></div><div>{module === "marketing" && <button onClick={() => setShowCampaignForm((value) => !value)}>Nova campanha</button>}<button onClick={() => void load()}><RefreshCw /> Actualizar</button></div></div>
    <div className="operationalStats"><div><span>Total carregado</span><strong>{all.length}</strong></div><div><span>Colecções ligadas</span><strong>{data ? Object.keys(data.collections).length : 0}</strong></div></div>
    <div className="operationalToolbar"><div>{Object.entries(meta.sets).map(([key, label]) => <button key={key} className={selected === key ? "active" : ""} onClick={() => setSelected(key)}>{label}<b>{data?.collections[key]?.length || 0}</b></button>)}</div><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Pesquisar…" /></div>
    {notice && <div className="operationalNotice">{notice}</div>}
    {module === "marketing" && showCampaignForm && <form className="supportComposer" onSubmit={createCampaign}><label htmlFor="campaign-title">Título da campanha</label><input id="campaign-title" value={campaignTitle} onChange={(event) => setCampaignTitle(event.target.value)} minLength={3} maxLength={160} required /><button className="primaryAction" type="submit">Criar rascunho</button></form>}
    <div className="operationalTable"><div className="operationalRow operationalHeader"><span>Nome / referência</span><span>Plataforma / detalhe</span><span>Estado</span><span>Actualização</span><span>Acções</span></div>
      {rows.map((row, index) => {
        const isKyc = module === "field" && !["restaurants", "couriers", "notes"].includes(selected);
        const media = Array.isArray(row._kyc_media) ? row._kyc_media as KycMedia[] : [];
        const name = pick(row, ["full_name", "church_name", "store_name", "name", "subject", "user_id"]);
        const id = String(row.id || row.user_id || index);
        const platform = String(row._platform || "");
        const canCorrect = platform === "DeliGo" || platform === "SARCA" || platform.includes("Comun");
        return <div className="operationalRow" key={id}><div><strong>{name}</strong><small>{pick(row, ["_subject_type", "ticket_number", "id", "user_id"])}</small></div><span>{pick(row, ["_platform", "phone", "city", "location", "role", "priority"])}</span><b className="operationalStatus">{pick(row, ["status", "kyc_status", "is_active"])}</b><span>{pick(row, ["updated_at", "created_at"])}</span><div className="rowActions">
          {module === "support" && selected === "tickets" && <><button onClick={() => setTicketId(id)}>Abrir conversa</button>{String(row.status) !== "resolved" && <button onClick={() => void setTicketStatus(id, "resolved")}>Resolver</button>}</>}
          {module === "marketing" && selected === "campaigns" && <>{String(row.status) !== "published" && <button onClick={() => void updateCampaign(id, "published")}>Publicar</button>}{String(row.status) !== "archived" && <button onClick={() => void updateCampaign(id, "archived")}>Arquivar</button>}</>}
          {isKyc && <button disabled={!media.length} onClick={() => setGallery({ name, media })}>Galeria ({media.length})</button>}
          {isKyc && data?.permissions?.canDecideKyc && <>{canCorrect && <button disabled={Boolean(kycBusy[id])} onClick={() => void decideKyc(row, "correction")}>Pedir correção</button>}<button disabled={Boolean(kycBusy[id])} onClick={() => void decideKyc(row, "reject")}>Rejeitar</button><button disabled={Boolean(kycBusy[id])} onClick={() => void decideKyc(row, "approve")}><CheckCircle2 /> Aprovar</button></>}
        </div></div>;
      })}
      {!rows.length && <div className="peopleEmpty">Nenhum registo corresponde à pesquisa.</div>}
    </div>
    {module === "support" && ticketId && <section className="supportConversation"><div className="supportConversationHead"><div><span>CONVERSA DO TICKET</span><h3>{pick(activeTicket || {}, ["subject", "title", "id"])}</h3></div><button onClick={() => setTicketId("")}>Fechar</button></div><div className="supportMessages">{ticketMessages.length ? ticketMessages.map((item, index) => <article key={String(item.id || index)}><strong>{pick(item, ["sender_name", "sender_role", "sender_id"])}</strong><p>{pick(item, ["text", "content", "message"])}</p><small>{pick(item, ["created_at", "updated_at"])}</small></article>) : <div className="peopleEmpty">Ainda não existem mensagens neste ticket.</div>}</div><form className="supportComposer" onSubmit={sendMessage}><label htmlFor="support-message">Mensagem</label><textarea id="support-message" value={message} onChange={(event) => setMessage(event.target.value)} minLength={2} maxLength={4000} required /><button className="primaryAction" type="submit">Enviar</button></form></section>}
    {gallery && <div className="kycGalleryBackdrop" role="dialog" aria-modal="true" onClick={() => setGallery(null)}><div className="kycGallery" onClick={(event) => event.stopPropagation()}><div className="kycGalleryHead"><div><span>DOCUMENTOS KYC</span><h3>{gallery.name}</h3></div><button onClick={() => setGallery(null)}>Fechar</button></div><div className="kycGalleryGrid">{gallery.media.map((item, index) => <a href={item.url} target="_blank" rel="noreferrer" key={`${item.url}-${index}`}><Image src={item.url} alt={item.label} width={640} height={480} unoptimized /><strong>{item.label}</strong></a>)}</div></div></div>}
  </section>;
}
