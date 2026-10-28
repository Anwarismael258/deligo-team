type Notice = Record<string, unknown>;
/** The notification centre contains incoming work and direct communications only. */
export function isRelevantNotification(row: Notice): boolean {
  const type = String(row.type || "").toLowerCase();
  const source = String(row.source_type || "").toLowerCase();
  if (["manual_communication", "internal_message", "support_message", "wallet_transfer_received", "wallet_transfer_sent", "balance_confirmation", "deposit_confirmed"].includes(type)) return true;
  if (["internal_message", "support_message", "manual_communication"].includes(source)) return true;
  // Do not turn audit, task or workflow activity into inbox noise.
  if (["audit", "audit_log", "task", "process_event", "financial_event"].includes(source)) return false;
  const text = `${type} ${row.title || ""} ${row.body || ""}`.toLowerCase();
  return /(?:new|novo|nova|created|submitted|received|recebido|recebida|criado|criada)/.test(text)
    && /(?:order|pedido|trip|ride|viagem|kyc|verifica|marketing|support_message)/.test(text);
}
