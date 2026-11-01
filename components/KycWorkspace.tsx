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
  const [view, setView] = useState("pending");
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [platform, setPlatform] = useState("all");
  const groups = useMemo(() => groupKycCases(rows), [rows]);
  const current = groups.find(group => group.id === selected);
  const titles: Record<string, string> = { all: "Todos", pending: "Pendentes", approved: "Aprovados", rejected: "Rejeitados" };
  const counts = { all: groups.length, pending: groups.filter(group => !["approved", "rejected", "suspended"].includes(group.status)).length, approved: groups.filter(group => group.status === "approved").length, rejected: groups.filter(group => group.status === "rejected").length };
  const platforms = Array.from(new Set(groups.map(group => group.platform).filter(Boolean)));
  const filtered = groups.filter(group => {
    const matchesView = view === "all" || view === "approved" ? group.status === view || (view === "all" && true) : view === "pending" ? !["approved", "rejected", "suspended"].includes(group.status) : group.status === view;
    const text = `${group.name} ${group.platform}`.toLowerCase();
    return matchesView && (!query.trim() || text.includes(query.trim().toLowerCase())) && (platform === "all" || group.platform === platform);
  });
  return <section className={styles.workspace} aria-label="Operações de Campo e verificações KYC">
    <header className={styles.header}><div><span className={styles.eyebrow}>HQ / OPERAÇÕES DE CAMPO</span><h2>Operações de Campo</h2><p>Acompanhamento de agentes, visitas e verificações KYC.</p></div><div className={styles.headerActions}><button>⇩ Exportar</button><button className={styles.primary} onClick={() => setView("pending")}>＋ Nova missão</button></div></header>
    <div className={styles.metrics}><article><i className={styles.metricDocument}>▤</i><span>KYC pendentes</span><strong>{counts.pending}</strong></article><article><i className={styles.metricSuccess}>✓</i><span>KYC aprovados</span><strong>{counts.approved}</strong></article><article><i className={styles.metricLocation}>⌖</i><span>Visitas hoje</span><strong>—</strong></article><article><i className={styles.metricAgents}>♧</i><span>Agentes em campo</span><strong>—</strong></article></div>
    {notice && <p className={styles.notice} role="status">{notice}</p>}
    <nav className={styles.tabs} aria-label="Vistas de operações"><button className={view === "all" ? styles.active : ""} onClick={() => { setView("all"); setSelected(null); }}>▤ Verificações KYC <b>{counts.all}</b></button><button className={view === "pending" ? styles.active : ""} onClick={() => { setView("pending"); setSelected(null); }}>▣ Missões e visitas</button><button onClick={() => setView("approved")}>♙ Agentes</button><button onClick={() => setView("rejected")}>◷ Histórico</button></nav>
    <div className={styles.body}>
      <div className={styles.queue}><div className={styles.filters}><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Pesquisar pessoa ou estabelecimento…"/><select value={platform} onChange={event => setPlatform(event.target.value)}><option value="all">Todas as plataformas</option>{platforms.map(item => <option key={item} value={item}>{item}</option>)}</select></div><div className={styles.pills}>{Object.entries(titles).map(([value, label]) => <button key={value} className={view === value ? styles.active : ""} onClick={() => { setView(value); setSelected(null); }}>{label} <b>{counts[value as keyof typeof counts] ?? 0}</b></button>)}</div><div className={styles.tableHead}><span>Entidade</span><span>Plataforma</span><span>Estado</span><span>Data</span><span>Ação</span></div><div className={styles.people}>{filtered.map(group => <article className={`${styles.person} ${selected === group.id ? styles.selected : ""}`} key={group.id} onClick={() => setSelected(group.id)}><div className={styles.avatar} aria-hidden="true">{group.name.slice(0, 2).toUpperCase()}</div><div className={styles.personName}><h3>{group.name}</h3><p>{group.documents.length} documento{group.documents.length === 1 ? "" : "s"}</p></div><span className={styles.platformName}>{group.platform}</span><span className={`${styles.status} ${group.status}`}>{statusName[group.status] || group.status}</span><small>—</small><button onClick={event => { event.stopPropagation(); setSelected(group.id); }}>{group.status === "approved" ? "Ver" : "Analisar"}</button></article>)}{!filtered.length && <p className={styles.empty}>Sem registos nesta fila.</p>}</div></div>
      {current && <aside className={styles.detail}><div className={styles.detailHeader}><div><span className={styles.detailEyebrow}>ANÁLISE DE KYC</span><h3>{current.name}</h3><p>{current.platform} · {statusName[current.status] || current.status}</p></div><button onClick={() => setSelected(null)}>×</button></div><div className={styles.detailInfo}><p>▣ <strong>{current.platform}</strong></p><p>◷ {current.documents.length} documento{current.documents.length === 1 ? "" : "s"} recebido{current.documents.length === 1 ? "" : "s"}</p></div><div className={styles.documents}>{current.documents.map(document => <DocumentCard key={document.id} document={document}>{canDecide && document.status !== "approved" && <><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "approve_kyc")}>Aprovar KYC</button><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "correct_kyc")}>Pedir correção</button><button disabled={Boolean(busy[document.caseId])} onClick={() => void onDecision(document.caseId, "reject_kyc")}>Rejeitar</button></>}</DocumentCard>)}</div><button className={styles.profileButton} onClick={() => onOpenProfile(current.rows[0])}>Abrir perfil completo ↗</button></aside>}
    </div>
  </section>;
}
