"use client";
import { useState } from "react";

export function ManualCommunication() {
  const [preview, setPreview] = useState(false);
  const [notice, setNotice] = useState("");
  const [sending, setSending] = useState(false);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    if (!preview) { setPreview(true); return; }
    if (!window.confirm("Confirmar o envio desta comunicação para os trabalhadores seleccionados?")) return;
    setSending(true);
    const response = await fetch("/api/notifications", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ audience: form.get("audience"), title: form.get("title"), body: form.get("body"), channels: ["in_app"] }) });
    const result = await response.json();
    setNotice(response.ok ? `Comunicação criada para ${result.recipientCount} destinatários.` : result.error || "Não foi possível criar a comunicação.");
    setSending(false);
    if (response.ok) { setPreview(false); event.currentTarget.reset(); }
  }
  return <section className="workflowInbox"><div className="workflowInboxHead"><div><span>INBOX INTERNA</span><h2>Comunicação interna</h2><p>Envie uma mensagem com título aos trabalhadores activos autorizados.</p></div></div><form className="financeEntryForm" onSubmit={submit}><label><span>Destinatários</span><select name="audience" defaultValue="all"><option value="all">Todos os trabalhadores autorizados</option><option value="finance">Finanças</option><option value="hr">Recursos Humanos</option><option value="support">Apoio ao Cliente</option><option value="operations">Operações</option></select></label><label><span>Título</span><input name="title" required maxLength={120} placeholder="Título da comunicação" /></label><label className="institutionalWide"><span>Mensagem</span><textarea name="body" required maxLength={1000} rows={5} placeholder="Escreva a mensagem..." /></label><div className="institutionalActions"><button type="submit" disabled={sending}>{preview ? "Confirmar e enviar" : "Pré-visualizar"}</button>{preview && <button type="button" onClick={() => setPreview(false)}>Editar</button>}</div></form>{notice && <div className="operationalNotice">{notice}</div>}</section>;
}
