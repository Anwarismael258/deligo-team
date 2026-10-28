"use client";
import { useMemo, useState } from "react";
import { documentsForCase, groupKycCases, type KycDocument, type KycRow } from "@/lib/kyc-presentation";
import { downloadDocument } from "@/lib/download-document";
import styles from "./KycWorkspace.module.css";

const statusName: Record<string, string> = { approved: "Aprovado", rejected: "Rejeitado", suspended: "Suspenso", submitted: "Pendente", pending: "Pendente", under_review: "Em análise", correction_requested: "Correção solicitada" };

function DocumentCard({ document, children }: { document: KycDocument; children?: React.ReactNode }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const save = async () => {
    if (!document.url || busy) return;
    setBusy(true);setError("");
    try { await downloadDocument(document.url, document.label); }
    catch (error) { setError(error instanceof Error ? error.message : "Não foi possível descarregar."); }
    finally { setBusy(false); }
  };
  return <article className={styles.document}>
    <h3>{document.label}</h3>
    {document.url ? <a className={styles.preview} href={document.url} target="_blank" rel="noreferrer"><img src={document.url} alt={document.label} loading="lazy" /></a> : <div className={styles.unavailable}>Documento indisponível</div>}
    <p>{statusName[document.status] || document.status}</p>
    <div className={styles.actions}>{document.url && <><a href={document.url} target="_blank" rel="noreferrer">Abrir</a><button disabled={busy} onClick={() => void save()}>{busy ? "A descarregar…" : "Guardar"}</button></>}{children}</div>
    {error && <p role="alert">{error}</p>}
  </article>;
}

export function KycDocumentGallery({ rows }: { rows: KycRow[] }) {
  return <div className={styles.documents}>{rows.flatMap(documentsForCase).map(document => <DocumentCard key={document.id} document={document} />)}</div>;
}

export default function KycWorkspace({ rows, notice, busy, canDecide, onDecision, onOpenProfile }: {
  rows: KycRow[]; notice: string; busy: Record<string, boolean>; canDecide: boolean;
  onDecision: (id: string, action: string) => Promise<void>; onOpenProfile: (row: KycRow) => void;
}) {
  const [view, setView] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const groups = useMemo(() => groupKycCases(rows), [rows]);
  const current = groups.find(group => group.id === selected && group.status !== "approved");
  const filtered = groups.filter(group => view === "approved" ? group.status === "approved" : view === "pending" ? !["approved", "rejected", "suspended"].includes(group.status) : group.status === view);
  const titles: Record<string, string> = { pending: "KYC pendentes", approved: "KYC aprovados", rejected: "KYC rejeitados", suspended: "KYC suspensos" };
  return <section className={styles.workspace} aria-label="KYC">
    <header className={styles.header}><div><h2>{current ? current.name : titles[view] || "KYC"}</h2><p>{current ? current.platform : "Validação de identidade e documentos"}</p></div>
      {(view || selected) && <button onClick={() => current ? setSelected(null) : (setView(""), setSelected(null))}>← Voltar</button>}
    </header>
    {notice && <p className={styles.notice} role="status">{notice}</p>}
    {!view && <label className={styles.selector}>Abrir fila KYC<select value="" onChange={event => { setView(event.target.value);setSelected(null); }}><option value="">Selecionar…</option>{Object.entries(titles).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>}
    {view && !current && <div className={styles.people}>{filtered.map(group => <article className={styles.person} key={group.id}><div className={styles.avatar} aria-hidden="true">{group.name.slice(0, 1)}</div><div><h3>{group.name}</h3><p>{group.platform} · {group.documents.length} documentos</p><span>{statusName[group.status] || group.status}</span></div><button onClick={() => view === "approved" ? onOpenProfile(group.rows[0]) : setSelected(group.id)}>{view === "approved" ? "Abrir perfil completo" : "Ver detalhes"}</button></article>)}{!filtered.length && <p className={styles.empty}>Sem registos nesta fila.</p>}</div>}
    {current && <><div className={styles.detailHeader}><p>{current.documents.length} documentos · {statusName[current.status] || current.status}</p><button onClick={() => onOpenProfile(current.rows[0])}>Abrir perfil completo</button></div><div className={styles.documents}>{current.documents.map(document => <DocumentCard key={document.id} document={document}>{canDecide && document.status !== "approved" && <><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "approve_kyc")}>Aprovar</button><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "correct_kyc")}>Pedir correção</button><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "reject_kyc")}>Rejeitar</button></>}</DocumentCard>)}</div></>}
  </section>;
}
