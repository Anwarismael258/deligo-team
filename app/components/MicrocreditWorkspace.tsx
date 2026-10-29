"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";

const statuses = [["pendente", "Pendente"], ["em_analise", "Em análise"], ["aprovado", "Aprovado"], ["recusado", "Recusado"], ["desembolsado", "Desembolsado"], ["pago", "Pago"], ["cancelado", "Cancelado"]];
const intakeActions: Record<string, string[]> = { pendente: ["em_analise", "recusado", "cancelado"], em_analise: ["aprovado", "recusado", "cancelado"] };
const actionLabels: Record<string, string> = { aprovado: "Confirmar" };
const money = (v: unknown) => `${Number(v || 0).toLocaleString("pt-MZ", { maximumFractionDigits: 2 })} MT`;
const date = (v: unknown) => v ? new Date(String(v)).toLocaleString("pt-MZ") : "";
const statusLabel = (status: string) => statuses.find(([value]) => value === status)?.[1] || status;
const documentLabels = [["bi_front", "BI frente"], ["bi_back", "BI verso"], ["income", "Comprovativo de rendimento"]] as const;
type MicrocreditRecord = {
  is_unread?:boolean; id: string; reference?: string; full_name?: string; phone?: string; employer?: string; amount?: number; total_due?: number; term_days?: number; status: string; bi_number?: string; nuit?: string; monthly_income?: number; created_at?: string;
  doc_folder?: string; bi_front_path?: string | null; bi_back_path?: string | null; income_path?: string | null;
  documents?: Partial<Record<(typeof documentLabels)[number][0], string | null>>;
};
type MicrocreditNote = { id: string; application_id: string; body: string; created_at?: string; author_id?: string };

export function MicrocreditWorkspace() {
  const [rows, setRows] = useState<MicrocreditRecord[]>([]), [notes, setNotes] = useState<MicrocreditNote[]>([]);
  const [q, setQ] = useState(""), [submittedQ, setSubmittedQ] = useState(""), [status, setStatus] = useState("todos");
  const [selected, setSelected] = useState<MicrocreditRecord | null>(null), [note, setNote] = useState(""), [notice, setNotice] = useState(""), [preview, setPreview] = useState<{ url: string; label: string; kind: "image" | "pdf"; zoom: number; rotation: number } | null>(null);
  const [savingNote, setSavingNote] = useState(false), [previewError, setPreviewError] = useState(false);
  const previewRef = useRef<HTMLDivElement>(null);
  const [page, setPage] = useState(0), [hasMore, setHasMore] = useState(false), [loading, setLoading] = useState(false);

  const loadBusy=useRef(false);
  const linkedOpened=useRef(false);
  const load = useCallback(async (targetPage = page, silent=false) => {
    if(loadBusy.current)return;loadBusy.current=true;
    if(!silent)setLoading(true);
    try {
      const params = new URLSearchParams({ status, page: String(targetPage), summary:"1" });
      if (submittedQ) params.set("q", submittedQ);
      const r = await fetch(`/api/microcredit?${params}`, { cache: "no-store" });
      const b = await r.json();
      if (!r.ok) { setNotice(b.error || "Não foi possível carregar."); return; }
      setRows((b.applications || []) as MicrocreditRecord[]); setNotes((b.notes || []) as MicrocreditNote[]); setHasMore(Boolean(b.hasMore)); setNotice("");
    } catch { setNotice("Não foi possível carregar os pedidos. Tente novamente."); }
    finally { loadBusy.current=false;setLoading(false); }
  }, [page, status, submittedQ]);

  useEffect(() => { const timer = window.setTimeout(() => void load(page), 0); return () => window.clearTimeout(timer); }, [load, page]);
  useEffect(() => {
    if (!preview) return;
    previewRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape") setPreview(null); };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [preview]);

  const openApplication=async(row:MicrocreditRecord)=>{
    setSelected(row);setPreview(null);
    if(!row.is_unread)return;
    try{const response=await fetch("/api/microcredit",{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({id:row.id,read:true})});if(response.ok){setRows(current=>current.map(item=>item.id===row.id?{...item,is_unread:false}:item));window.dispatchEvent(new Event("hq-notifications-updated"));}}catch{}
  };
  useEffect(()=>{let cancelled=false;let timer:ReturnType<typeof setTimeout>;const poll=async()=>{if(document.visibilityState!=="hidden")await load(page,true);if(!cancelled)timer=setTimeout(poll,5000)};timer=setTimeout(poll,5000);return()=>{cancelled=true;clearTimeout(timer)}},[load,page]);
  useEffect(()=>{if(linkedOpened.current)return;const id=new URLSearchParams(window.location.search).get("application");const row=rows.find(item=>item.id===id);if(row){linkedOpened.current=true;void openApplication(row)}},[rows]);

  const submitSearch = (event: FormEvent) => { event.preventDefault(); setPage(0); setSubmittedQ(q.trim().slice(0, 120)); };
  const documentUrl = (key: (typeof documentLabels)[number][0], fallback: string | null | undefined) => {
    const path = selected?.[`${key}_path` as "bi_front_path" | "bi_back_path" | "income_path"];
    // Prefer the authenticated proxy when the original storage path exists.
    // Signed URLs can expire while a detail modal remains open; the proxy is
    // authorized per request and keeps private documents viewable.
    if (path) return `/api/microcredit/document?path=${encodeURIComponent(path)}&folder=${encodeURIComponent(selected?.doc_folder || "")}`;
    if (fallback) return fallback;
    return "";
  };
  const documentKind = (key: (typeof documentLabels)[number][0], fallback: string | null | undefined) => {
    const value = selected?.[`${key}_path` as "bi_front_path" | "bi_back_path" | "income_path"] || fallback || "";
    return /\.pdf(?:$|[?#])/i.test(value) ? "pdf" : "image";
  };
  const openDocument = (url: string, label: string, kind: "image" | "pdf") => {
    setPreviewError(false);
    setPreview({ url, label, kind, zoom: 1, rotation: 0 });
  };
  const updatePreview = (change: Partial<NonNullable<typeof preview>>) => setPreview(current => current ? { ...current, ...change } : current);
  const save = async (body: Record<string, unknown>) => {
    if (!selected) return;
    if (typeof body.status === "string") {
      const target = body.status;
      if (!(intakeActions[selected.status] || []).includes(target)) { setNotice("Esta alteração requer o procedimento controlado da Central."); return; }
      if (!window.confirm(`${selected.reference}: ${statusLabel(selected.status)} → ${statusLabel(target)}?`)) return;
    }
    const r = await fetch("/api/microcredit", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: selected.id, ...body }) });
    const b = await r.json();
    if (!r.ok) { setNotice(b.error || "Não foi possível guardar."); return; }
    await load(page); if (b.application) setSelected(b.application); setNote(""); setNotice(b.deliveryWarning ? `Estado guardado, mas a entrega do PDF ficou pendente (${b.deliveryWarning}). Configure o WhatsApp e tente novamente.` : "Alteração guardada.");
  };
  const saveNote = async () => {
    if (!note.trim() || savingNote) return;
    setSavingNote(true);
    try { await save({ note }); } finally { setSavingNote(false); }
  };

  return <section className="financeWorkspace">
    <form className="peopleSearchBar" onSubmit={submitSearch}><input value={q} onChange={e => setQ(e.target.value)} maxLength={120} placeholder="Nome, referência, telefone, BI ou NUIT"/><button type="submit" disabled={loading}>Pesquisar</button><select value={status} onChange={e => { setPage(0); setStatus(e.target.value); }} disabled={loading}><option value="todos">Todos os estados</option>{statuses.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select><b>{rows.length} pedidos</b></form>
    {notice && <div className="operationalNotice">{notice}</div>}
    <div className="procurementList">{loading ? <div className="peopleEmpty">A carregar pedidos…</div> : rows.map(r => <button key={r.id} className={r.is_unread?"microcreditUnread":""} onClick={() => void openApplication(r)}><div><strong>{r.is_unread&&<em className="microcreditUnreadBadge">Não lido</em>}{r.reference} · {r.full_name}</strong><span>{r.phone} · recebido {date(r.created_at)}</span></div><b>{money(r.amount)} · {statusLabel(r.status)}</b></button>)}{!loading && !rows.length && <div className="peopleEmpty">Nenhum pedido recebido.</div>}</div>
    <div className="peopleSearchBar"><button disabled={loading || page === 0} onClick={() => setPage(value => value - 1)}>Página anterior</button><span>Página {page + 1}</span><button disabled={loading || !hasMore} onClick={() => setPage(value => value + 1)}>Página seguinte</button></div>
    {selected && <div className="employeeDetail"><div className="employeeDetailHead"><div><span>PEDIDO {selected.reference}</span><h3>{selected.full_name}</h3><p>{selected.phone} · {selected.employer || "Sem empregador"}</p></div><button onClick={() => { setSelected(null); setPreview(null); }}>Fechar</button></div><div className="employeeDetailGrid"><article><span>Valor</span><strong>{money(selected.amount)}</strong></article><article><span>Total a pagar</span><strong>{money(selected.total_due)}</strong></article><article><span>Prazo</span><strong>{selected.term_days} dias</strong></article><article><span>Estado</span><strong>{statusLabel(selected.status)}</strong></article></div><div className="peopleSearchBar">{(intakeActions[selected.status] || []).map(v => <button key={v} onClick={() => void save({ status: v })}>{actionLabels[v] || statusLabel(v)}</button>)}</div><h3>Dados do cliente</h3><p>BI: {selected.bi_number} · NUIT: {selected.nuit} · Salário: {money(selected.monthly_income)}</p><h3>Documentos do pedido</h3><div className="microcreditDocuments">{documentLabels.map(([key, label]) => { const url = documentUrl(key, selected.documents?.[key]); const kind = documentKind(key, selected.documents?.[key]); return url ? <button type="button" className="microcreditDocumentCard" key={key} onClick={() => openDocument(url, label, kind)}><span className="microcreditDocumentMedia">{kind === "pdf" ? <span className="microcreditPdfBadge">PDF</span> : <img src={url} alt={label} loading="lazy" width={640} height={480}/>}</span><b>{label}</b><span>Ver documento · abrir privado ↗</span></button> : <span className="microcreditDocumentMissing" key={key}>{label}<span>Não disponível</span></span>; })}</div><h3>Notas internas</h3><textarea value={note} onChange={e => setNote(e.target.value)} maxLength={2000} placeholder="Nota para a equipa financeira"/><button className="primaryAction" disabled={!note.trim() || savingNote} onClick={() => void saveNote()}>{savingNote ? "A guardar…" : "Guardar nota"}</button><div className="procurementList">{notes.filter(n => n.application_id === selected.id).map(n => <article key={n.id}><strong>{n.body}</strong><span>{date(n.created_at)} · Autor: {n.author_id || "—"}</span></article>)}</div></div>}
    {preview && <div className="microcreditPreviewBackdrop" onClick={() => setPreview(null)}><div className="microcreditPreview" ref={previewRef} tabIndex={-1} role="dialog" aria-modal="true" aria-label={preview.label} onClick={event => event.stopPropagation()}><div className="microcreditPreviewHead"><strong>{preview.label}</strong><div className="microcreditPreviewTools">{preview.kind === "image" && <><button type="button" onClick={() => updatePreview({ zoom: Math.min(3, preview.zoom + .25) })}>Zoom +</button><button type="button" onClick={() => updatePreview({ zoom: Math.max(.5, preview.zoom - .25) })}>Zoom −</button><button type="button" onClick={() => updatePreview({ rotation: (preview.rotation + 90) % 360 })}>Rodar</button><button type="button" onClick={() => updatePreview({ zoom: 1, rotation: 0 })}>Ajustar</button></>}<button type="button" onClick={() => setPreview(null)}>Fechar</button></div></div>{previewError ? <div className="microcreditPreviewError">Não foi possível abrir este documento.<button type="button" onClick={() => { setPreviewError(false); updatePreview({ url: `${preview.url}${preview.url.includes("?") ? "&" : "?"}retry=${Date.now()}` }); }}>Tentar novamente</button></div> : preview.kind === "pdf" ? <iframe title={preview.label} src={preview.url} className="microcreditPdfViewer" onError={() => setPreviewError(true)}/> : <img src={preview.url} alt={preview.label} width={1200} height={900} onError={() => setPreviewError(true)} style={{ transform: `scale(${preview.zoom}) rotate(${preview.rotation}deg)` }}/>}<a href={preview.url} target="_blank" rel="noreferrer">Abrir documento privado ↗</a></div></div>}
  </section>;
}
