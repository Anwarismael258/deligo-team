"use client";

import { FormEvent, useEffect, useState } from "react";

const pageSize = 40;
const statuses = [["pendente", "Pendente"], ["em_analise", "Em análise"], ["aprovado", "Aprovado"], ["recusado", "Recusado"], ["desembolsado", "Desembolsado"], ["pago", "Pago"], ["cancelado", "Cancelado"]];
const intakeActions: Record<string, string[]> = { pendente: ["em_analise", "recusado", "cancelado"], em_analise: ["recusado", "cancelado"] };
const money = (v: unknown) => `${Number(v || 0).toLocaleString("pt-MZ", { maximumFractionDigits: 2 })} MT`;
const date = (v: unknown) => v ? new Date(String(v)).toLocaleString("pt-MZ") : "";
const statusLabel = (status: string) => statuses.find(([value]) => value === status)?.[1] || status;
const documentLabels = [["bi_front", "BI frente"], ["bi_back", "BI verso"], ["income", "Comprovativo de rendimento"]] as const;

export function MicrocreditWorkspace() {
  const [rows, setRows] = useState<any[]>([]), [notes, setNotes] = useState<any[]>([]);
  const [q, setQ] = useState(""), [submittedQ, setSubmittedQ] = useState(""), [status, setStatus] = useState("todos");
  const [selected, setSelected] = useState<any>(null), [note, setNote] = useState(""), [notice, setNotice] = useState("");
  const [page, setPage] = useState(0), [hasMore, setHasMore] = useState(false), [loading, setLoading] = useState(false);

  const load = async (targetPage = page) => {
    setLoading(true);
    try {
      const params = new URLSearchParams({ status, page: String(targetPage) });
      if (submittedQ) params.set("q", submittedQ);
      const r = await fetch(`/api/microcredit?${params}`, { cache: "no-store" });
      const b = await r.json();
      if (!r.ok) { setNotice(b.error || "Não foi possível carregar."); return; }
      setRows(b.applications || []); setNotes(b.notes || []); setHasMore(Boolean(b.hasMore)); setNotice("");
    } catch { setNotice("Não foi possível carregar os pedidos. Tente novamente."); }
    finally { setLoading(false); }
  };

  useEffect(() => { void load(page); }, [status, page, submittedQ]);

  const submitSearch = (event: FormEvent) => { event.preventDefault(); setPage(0); setSubmittedQ(q.trim().slice(0, 120)); };
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
    await load(page); if (b.application) setSelected(b.application); setNote(""); setNotice("Alteração guardada.");
  };

  return <section className="financeWorkspace">
    <div className="financeHero"><div><span>TRIUNFAL MICROCRÉDITO</span><h2>Pedidos recebidos do site institucional</h2><p>Analise pedidos, documentos e estados com histórico protegido.</p></div><button disabled={loading} onClick={() => void load(page)}>Actualizar</button></div>
    <form className="peopleSearchBar" onSubmit={submitSearch}><input value={q} onChange={e => setQ(e.target.value)} maxLength={120} placeholder="Nome, referência, telefone, BI ou NUIT"/><button type="submit" disabled={loading}>Pesquisar</button><select value={status} onChange={e => { setPage(0); setStatus(e.target.value); }} disabled={loading}><option value="todos">Todos os estados</option>{statuses.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select><b>{rows.length} pedidos</b></form>
    {notice && <div className="operationalNotice">{notice}</div>}
    <div className="procurementList">{loading ? <div className="peopleEmpty">A carregar pedidos…</div> : rows.map(r => <button key={r.id} onClick={() => setSelected(r)}><div><strong>{r.reference} · {r.full_name}</strong><span>{r.phone} · recebido {date(r.created_at)}</span></div><b>{money(r.amount)} · {statusLabel(r.status)}</b></button>)}{!loading && !rows.length && <div className="peopleEmpty">Nenhum pedido recebido.</div>}</div>
    <div className="peopleSearchBar"><button disabled={loading || page === 0} onClick={() => setPage(value => value - 1)}>Página anterior</button><span>Página {page + 1}</span><button disabled={loading || !hasMore} onClick={() => setPage(value => value + 1)}>Página seguinte</button></div>
    {selected && <div className="employeeDetail"><div className="employeeDetailHead"><div><span>PEDIDO {selected.reference}</span><h3>{selected.full_name}</h3><p>{selected.phone} · {selected.employer || "Sem empregador"}</p></div><button onClick={() => setSelected(null)}>Fechar</button></div><div className="employeeDetailGrid"><article><span>Valor</span><strong>{money(selected.amount)}</strong></article><article><span>Total a pagar</span><strong>{money(selected.total_due)}</strong></article><article><span>Prazo</span><strong>{selected.term_days} dias</strong></article><article><span>Estado</span><strong>{statusLabel(selected.status)}</strong></article></div><div className="peopleSearchBar">{(intakeActions[selected.status] || []).map(v => <button key={v} onClick={() => void save({ status: v })}>{statusLabel(v)}</button>)}</div><h3>Dados do cliente</h3><p>BI: {selected.bi_number} · NUIT: {selected.nuit} · Salário: {money(selected.monthly_income)}</p><h3>Documentos do pedido</h3><div className="microcreditDocuments">{documentLabels.map(([key, label]) => selected.documents?.[key] ? <a key={key} href={selected.documents[key]} target="_blank" rel="noreferrer">{label}<span>Link privado, expira em 5 min ↗</span></a> : <span className="microcreditDocumentMissing" key={key}>{label}<span>Não disponível</span></span>)}</div><h3>Notas internas</h3><textarea value={note} onChange={e => setNote(e.target.value)} maxLength={2000} placeholder="Nota para a equipa financeira"/><button className="primaryAction" disabled={!note.trim()} onClick={() => void save({ note })}>Guardar nota</button><div className="procurementList">{notes.filter(n => n.application_id === selected.id).map(n => <article key={n.id}><strong>{n.body}</strong><span>{date(n.created_at)} · Autor: {n.author_id || "—"}</span></article>)}</div></div>}
  </section>;
}
