"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

type Platform = "deligo" | "comunhao" | "taomoz" | "sarca" | "mestre24";
type EventRow = { id: string; event_type?: string; status?: string; ride_id?: string; details?: string; created_at?: string; assigned_to?: string };
const platformList: Array<{ id: Platform; label: string }> = [{ id: "deligo", label: "DeliGo" }, { id: "comunhao", label: "Comunhão" }, { id: "taomoz", label: "DeliGo Market" }, { id: "sarca", label: "SARCA" }, { id: "mestre24", label: "Mestre24" }];

export function SafetyCenterWorkspace() {
  const [platform, setPlatform] = useState<Platform>("sarca");
  const [events, setEvents] = useState<EventRow[]>([]);
  const [configured, setConfigured] = useState(false);
  const [error, setError] = useState("");
  const [note, setNote] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState("");
  const selectedLabel = platformList.find(item => item.id === platform)?.label || platform;

  const load = useCallback(async () => {
    setError("");
    try {
      const response = await fetch(`/api/security/events?platform=${platform}`, { cache: "no-store" });
      const payload = await response.json() as { events?: EventRow[]; configured?: boolean; error?: string };
      if (!response.ok) throw new Error(payload.error || "Fonte de segurança indisponível.");
      setEvents(payload.events || []); setConfigured(Boolean(payload.configured));
    } catch (cause) { setEvents([]); setConfigured(false); setError(cause instanceof Error ? cause.message : "Fonte de segurança indisponível."); }
  }, [platform]);

  useEffect(() => { void load(); }, [load]);
  const pending = useMemo(() => events.filter(event => event.status !== "resolved").length, [events]);

  async function update(eventId: string, action: "acknowledge" | "resolve") {
    setBusy(eventId); setError("");
    try {
      const response = await fetch("/api/security/events", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ platform, eventId, action, resolutionNote: note[eventId] }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error || "Não foi possível actualizar a ocorrência.");
      await load();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível actualizar a ocorrência."); } finally { setBusy(""); }
  }

  return <section className="securityEventsWorkspace">
    <div className="securityEventsHeader"><div><span>SEGURANÇA · TODAS AS PLATAFORMAS</span><h2>Ocorrências de segurança</h2><p>Alertas recebidos de SARCA, DeliGo Market e futuras plataformas, com isolamento por origem.</p></div><button type="button" onClick={() => void load()}>Actualizar</button></div>
    <div className="securityPlatformTabs">{platformList.map(item => <button key={item.id} type="button" className={platform === item.id ? "active" : ""} onClick={() => setPlatform(item.id)}>{item.label}</button>)}</div>
    <div className="securityEventsSummary"><article><span>Fonte</span><strong>{configured ? "Ligada" : "Não configurada"}</strong></article><article><span>Ocorrências pendentes</span><strong>{pending}</strong></article><article><span>Estado</span><strong>{error ? "Indisponível" : configured ? "Verificado" : "A aguardar integração"}</strong></article></div>
    {error && <div className="safeNotice"><b>Não foi possível consultar {selectedLabel}</b><span>{error}</span><button type="button" onClick={() => void load()}>Tentar novamente</button></div>}
    {!error && !configured && <div className="securityEmpty"><strong>{selectedLabel}: integração de segurança não configurada</strong><span>A plataforma pode ser acrescentada quando publicar o endpoint de ocorrências com o mesmo contrato de segurança da Central.</span></div>}
    {!error && configured && <div className="securityEventList">{events.map(event => <article className={`securityEventRow ${event.status || "open"}`} key={event.id}><div><strong>{String(event.event_type || "Ocorrência").replaceAll("_", " ")}</strong><span>{event.status === "acknowledged" ? "Assumida" : event.status === "resolved" ? "Resolvida" : "Aberta"}{event.ride_id ? ` · referência ${event.ride_id}` : ""}</span><small>{event.details || "Sem detalhes adicionais"} · {event.created_at ? new Date(event.created_at).toLocaleString("pt-MZ") : "Data indisponível"}</small></div>{event.status !== "resolved" && <div className="securityEventActions">{event.status !== "acknowledged" && <button type="button" disabled={busy === event.id} onClick={() => void update(event.id, "acknowledge")}>Assumir</button>}<input value={note[event.id] || ""} onChange={e => setNote(current => ({ ...current, [event.id]: e.target.value }))} placeholder="Nota obrigatória para resolver"/><button type="button" disabled={busy === event.id || (note[event.id] || "").trim().length < 3} onClick={() => void update(event.id, "resolve")}>Resolver</button></div>}</article>)}{!events.length && <div className="securityEmpty"><strong>Sem ocorrências abertas</strong><span>Não existem alertas reais recebidos nesta fonte.</span></div>}</div>}
  </section>;
}
