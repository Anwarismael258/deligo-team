"use client";
import { useState } from "react";

export function ManualCommunication() {
  const [preview, setPreview] = useState(false);
  const [notice, setNotice] = useState("");
  const [sending, setSending] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const title = String(form.get("title") || "").trim();
    const body = String(form.get("body") || "").trim();
    setNotice("");
    if (title.length < 3 || body.length < 3) { setNotice("Preencha um título e uma mensagem com pelo menos 3 caracteres."); return; }
    if (!preview) { setPreview(true); return; }
    setSending(true);
    try {
      const response = await fetch("/api/notifications", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title, body }) });
      const raw = await response.text();
      let result: { recipientCount?: number; error?: string } = {};
      try { result = raw ? JSON.parse(raw) : {}; } catch { result = { error: "Resposta inválida do servidor." }; }
      setNotice(response.ok ? `Comunicação enviada para ${result.recipientCount || 0} trabalhadores activos.` : result.error || "Não foi possível enviar a comunicação.");
      if (response.ok) { setPreview(false); event.currentTarget.reset(); }
    } catch { setNotice("Não foi possível contactar o servidor. Tente novamente."); }
    finally { setSending(false); }
  }
 return <section className="workflowInbox"><div className="workflowInboxHead"><div><span>INBOX INTERNA</span><h2>Comunicação interna</h2><p>Escreva uma mensagem com título. Todos os trabalhadores activos recebem a notificação.</p></div></div><form className="financeEntryForm" onSubmit={submit}><label><span>Título</span><input name="title" required minLength={3} maxLength={120} placeholder="Título da comunicação" /></label><label className="institutionalWide"><span>Mensagem</span><textarea name="body" required minLength={3} maxLength={1000} rows={5} placeholder="Escreva a mensagem..." /></label>{preview && <div className="safeNotice"><b>Pré-visualização</b><span>Esta mensagem será enviada a todos os trabalhadores activos.</span></div>}<div className="institutionalActions"><button type="submit" disabled={sending}>{sending ? "A enviar…" : preview ? "Confirmar e enviar" : "Pré-visualizar"}</button>{preview && <button type="button" onClick={() => { setPreview(false); setNotice(""); }}>Editar</button>}</div></form>{notice && <div className="operationalNotice">{notice}</div>}</section>;
}
