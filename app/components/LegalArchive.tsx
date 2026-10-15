"use client";
import { useEffect, useState } from "react";

type DocumentRow = { name: string; folder: string; category: string; size: number | null; updated_at: string | null };
export function LegalArchive() {
  const [documents, setDocuments] = useState<DocumentRow[]>([]);
  const [filter, setFilter] = useState("all");
  const [notice, setNotice] = useState("");
  useEffect(() => { fetch("/api/legal/archive", { cache: "no-store" }).then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(j.error); setDocuments(j.documents || []); }).catch((e) => setNotice(e.message || "Não foi possível carregar o arquivo.")); }, []);
  const visible = filter === "all" ? documents : documents.filter((d) => d.folder === filter);
  const download = async (doc: DocumentRow) => { const r = await fetch("/api/legal/archive", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ folder: doc.folder, name: doc.name }) }); const j = await r.json(); if (r.ok && j.url) window.open(j.url, "_blank", "noopener,noreferrer"); else setNotice(j.error || "Download indisponível."); };
  return <section className="financePanel" style={{ marginTop: 24 }}><div className="panelTitle"><div><span>ARQUIVO PRIVADO</span><h2>Documentos da empresa</h2><p>Bucket privado · acesso autorizado · links de download expiram em 5 minutos.</p></div><strong>{documents.length} documentos</strong></div><div className="financeEntryForm"><label><span>Categoria</span><select value={filter} onChange={(e) => setFilter(e.target.value)}><option value="all">Todas</option>{Array.from(new Map(documents.map((d) => [d.folder, d.category]))).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label></div>{notice && <div className="operationalNotice">{notice}</div>}<div className="procurementList">{visible.map((doc) => <article key={`${doc.folder}/${doc.name}`}><div><strong>{doc.name}</strong><span>{doc.category} · {doc.size ? `${Math.round(doc.size / 1024)} KB` : "tamanho indisponível"}</span></div><button onClick={() => void download(doc)}>Download seguro</button></article>)}{!visible.length && <div className="peopleEmpty">Nenhum documento encontrado.</div>}</div></section>;
}
