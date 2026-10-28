"use client";
import { useCallback, useEffect, useState } from "react";
import { mozPhone, smsSegments } from "@/lib/sms-campaigns";
import styles from "./sms.module.css";
type User = { user_id: string; full_name?: string; display_name?: string; primary_phone?: string };
type Campaign = { id: string; title: string; message: string; sender_id: string; status: string; segments: number; max_recipients: number; target_user_id: string | null };
type Data = { balance: { balance: number; unitPrice: number } | null; apps: string[]; app: string; campaigns: Campaign[]; users: User[]; consents: { user_id: string; phone: string; allowed: boolean }[]; offset: number; hasMore: boolean; liveEnabled: boolean; canSend: boolean };
type Detail = { campaign: Campaign; counts: Record<string, number>; recordedCost: number };
const names: Record<string, string> = { draft: "Rascunho", ready: "Autorizada / na fila", paused: "Pausada", cancelled: "Cancelada", completed: "Processada", queued: "Na fila", sending: "Em envio", accepted: "Aceites pelo fornecedor", failed: "Falhadas", unknown: "Resultado desconhecido" };
export default function SmsMarketingPage() {
  const [data, setData] = useState<Data | null>(null);
  const [app, setApp] = useState("");
  const [offset, setOffset] = useState(0);
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [detail, setDetail] = useState<Detail | null>(null);
  const [review, setReview] = useState<Campaign | null>(null);
  const [consentUser, setConsentUser] = useState<User | null>(null);
  const segments = smsSegments(message);
  const refresh = useCallback(async (signal?: AbortSignal) => {
    const response = await fetch(`/api/marketing/sms?app=${encodeURIComponent(app)}&offset=${offset}`, { signal });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Não foi possível carregar SMS.");
    setData(result);
  }, [app, offset]);
  useEffect(() => {
    const controller = new AbortController();
    refresh(controller.signal).catch(error => { if (!controller.signal.aborted) setNotice(error.message); });
    return () => controller.abort();
  }, [refresh]);
  async function mutate(payload: Record<string, unknown>) {
    setBusy(true); setNotice("");
    try {
      const response = await fetch("/api/marketing/sms", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...payload, app: data?.app }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Operação falhou.");
      setNotice(payload.action === "send" ? result.processed ? `SMS processado: ${names[result.status] || result.status}.` : "Sem mensagem disponível; atualize o detalhe." : "Operação guardada.");
      await refresh();
      return true;
    } catch (error) { setNotice(error instanceof Error ? error.message : "Falha de ligação."); return false; }
    finally { setBusy(false); }
  }
  async function loadDetail(id: string) {
    try {
      const response = await fetch(`/api/marketing/sms?app=${encodeURIComponent(data?.app || "")}&campaign=${id}`);
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      setDetail(result);
    } catch { setNotice("Não foi possível carregar o detalhe."); }
  }
  return <main className={styles.workspace}>
    <header className={styles.header}><div><a href="/">← Voltar à Central</a><p>MARKETING · MOZESMS</p><h1>Campanhas SMS</h1><span>Comunicação da DeliGo no telemóvel dos teus utilizadores.</span></div><span className={styles.badge}>{data?.liveEnabled ? "Envios habilitados" : "Envios reais desativados"}</span></header>
    <div className={styles.toolbar}><label>Plataforma<select disabled={busy} value={data?.app || ""} onChange={event => { setData(null); setApp(event.target.value); setOffset(0); setDetail(null); setReview(null); }}>{(data?.apps || []).map(value => <option key={value}>{value}</option>)}</select></label><button disabled={busy} onClick={() => { refresh().catch(() => setNotice("Falha ao atualizar.")); }}>Atualizar</button></div>
    <p role="status" aria-live="polite">{notice}</p>
    {!data ? <p>A carregar…</p> : <>
      <section className={styles.grid}>
        <form className={styles.card} onSubmit={async event => {
          event.preventDefault(); const form = event.currentTarget; const fields = new FormData(form);
          if (await mutate({ action: "create", title: fields.get("title"), message, maxRecipients: Number(fields.get("max")), targetUserId: fields.get("target") })) { form.reset(); setMessage(""); }
        }}>
          <h2>Nova campanha</h2>
          <label>Título interno<input name="title" required minLength={3} maxLength={120} /></label>
          <label>Público<select name="target"><option value="">Todos os contactos elegíveis desta plataforma</option>{data.users.filter(user => mozPhone(user.primary_phone || "")).map(user => <option key={user.user_id} value={user.user_id}>Teste individual: {user.full_name || user.display_name || user.primary_phone}</option>)}</select></label>
          <label>Máximo de destinatários<input name="max" type="number" min={1} max={10000} defaultValue={10} required /></label>
          <label>Mensagem<textarea value={message} onChange={event => setMessage(event.target.value)} maxLength={1000} required rows={5} placeholder="DELIGO: ... Inclua uma forma de cancelar publicidade." /></label>
          <small>{segments.encoding} · {segments.units} unidades · {segments.segments} segmento(s) por destinatário</small>
          <p>{data.balance ? `Saldo: ${data.balance.balance.toFixed(2)} MT · estimativa por destinatário: ${(segments.segments * data.balance.unitPrice).toFixed(2)} MT.` : "Saldo indisponível; os envios ficam bloqueados sem confirmação do saldo."}</p>
          <p>O remetente será o nome aprovado configurado na MozeSMS. A cobrança é por segmento. O preço do teu plano deve ser confirmado na MozeSMS.</p>
          <button disabled={busy || !message.trim()} type="submit">Guardar rascunho</button>
        </form>
        <section className={styles.card}><h2>Campanhas recentes</h2>{data.campaigns.length === 0 ? <p>Nenhuma campanha nesta plataforma.</p> : data.campaigns.map(campaign => <article className={styles.campaign} key={campaign.id}><strong>{campaign.title}</strong><span>{names[campaign.status]} · {campaign.sender_id}</span><div className={styles.actions}><button disabled={busy} onClick={() => loadDetail(campaign.id)}>Resultados</button>{campaign.status === "draft" && data.canSend && <button disabled={busy} onClick={() => setReview(campaign)}>Rever e autorizar</button>}{campaign.status === "ready" && <><button disabled={busy} onClick={() => mutate({ action: "pause", id: campaign.id })}>Pausar</button>{data.canSend && <button disabled={busy || !data.liveEnabled} onClick={async () => { await mutate({ action: "send", id: campaign.id }); await loadDetail(campaign.id); }}>Enviar próximo SMS</button>}</>}{campaign.status === "paused" && data.canSend && <button disabled={busy} onClick={() => mutate({ action: "resume", id: campaign.id })}>Retomar fila</button>}{["draft", "ready", "paused"].includes(campaign.status) && <button disabled={busy} onClick={() => mutate({ action: "cancel", id: campaign.id })}>Cancelar pendentes</button>}</div></article>)}</section>
      </section>
      {review && <section className={styles.card} aria-labelledby="review-title"><h2 id="review-title">Autorizar: {review.title}</h2><p>De: <strong>{review.sender_id}</strong></p><blockquote>{review.message}</blockquote><p>{review.target_user_id ? "Teste individual" : "Todos os contactos elegíveis"} · máximo {review.max_recipients} destinatários · até {review.max_recipients * review.segments} segmentos.</p><p>A autorização coloca a campanha na fila. Um processador configurado pode começar os envios. Pausar ou cancelar não retira SMS já em envio.</p><div className={styles.actions}><button disabled={busy} onClick={async () => { if (await mutate({ action: "prepare", id: review.id })) setReview(null); }}>Autorizar esta campanha</button><button disabled={busy} onClick={() => setReview(null)}>Voltar</button></div></section>}
      {detail && <section className={styles.card}><h2>{detail.campaign.title} · resultados</h2><div className={styles.actions}>{Object.entries(detail.counts).map(([state, count]) => <span className={styles.badge} key={state}>{names[state]}: {count}</span>)}</div><p>Custo registado pelo fornecedor: {detail.recordedCost.toFixed(2)} MT.</p><p>“Aceite” não confirma entrega. Resultados desconhecidos exigem reconciliação na MozeSMS e não são reenviados automaticamente.</p><button onClick={() => loadDetail(detail.campaign.id)}>Atualizar resultados</button></section>}
      <section className={styles.card}><h2>Contactos e consentimentos</h2><p>O registo ou OTP não autoriza publicidade. Regista apenas autorizações comprovadas. Números repetidos recebem uma mensagem por campanha.</p><div className={styles.table}><table><thead><tr><th>Utilizador</th><th>Telefone</th><th>Consentimento SMS</th><th>Ação</th></tr></thead><tbody>{data.users.map(user => {
        const phone = mozPhone(user.primary_phone || ""); const consent = data.consents.find(item => item.user_id === user.user_id && item.phone === phone);
        return <tr key={user.user_id}><td>{user.full_name || user.display_name || "Utilizador"}</td><td>{phone || "Inválido / indisponível"}</td><td>{consent?.allowed ? "Registado" : "Sem autorização"}</td><td><button disabled={busy || !phone} onClick={() => setConsentUser(user)}>Gerir</button></td></tr>;
      })}</tbody></table></div><div className={styles.actions}><button disabled={offset === 0 || busy} onClick={() => setOffset(value => Math.max(0, value - 100))}>Anterior</button><span>Página {offset / 100 + 1}</span><button disabled={!data.hasMore || busy} onClick={() => setOffset(value => value + 100)}>Seguinte</button></div></section>
      {consentUser && <form className={styles.card} onSubmit={async event => { event.preventDefault(); const fields = new FormData(event.currentTarget); if (await mutate({ action: "consent", userId: consentUser.user_id, allowed: fields.get("allowed") === "yes", evidence: fields.get("evidence") })) setConsentUser(null); }}><h2>Consentimento · {consentUser.full_name || consentUser.primary_phone}</h2><label>Estado<select name="allowed"><option value="no">Recusar / retirar consentimento</option><option value="yes">Autorização comprovada para SMS de marketing</option></select></label><label>Referência da prova ou motivo<textarea name="evidence" required minLength={5} maxLength={1000} /></label><p>Retirar consentimento como Super Admin bloqueia também o número nas restantes campanhas. Reativação global exige revisão técnica.</p><div className={styles.actions}><button disabled={busy}>Guardar consentimento</button><button type="button" onClick={() => setConsentUser(null)}>Fechar</button></div></form>}
    </>}
  </main>;
}
