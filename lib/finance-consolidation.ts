export type InternalReconciliationState = "RECONCILIADO_INTERNAMENTE" | "DIVERGENTE" | "PENDENTE" | "FONTE_INSUFICIENTE" | "NAO_APLICAVEL";

export type CanonicalSourceRow = {
  metric: string;
  platform: string;
  primarySource: string;
  validationSource: string;
  formula: string;
  ownership: string;
  currency: "MZN";
  eventIdentifier: string;
  accountingPeriod: string;
};

export const canonicalSourceMatrix: readonly CanonicalSourceRow[] = [
  { metric: "GMV", platform: "DeliGo Eats", primarySource: "hq.platform_financial_events.gross_amount", validationSource: "order_financial_snapshots", formula: "soma de gross_amount confirmado", ownership: "transacção e obrigações de terceiros", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
  { metric: "Receita da plataforma", platform: "DeliGo Eats", primarySource: "hq.platform_financial_events.platform_fee", validationSource: "hq.corporate_revenue_credits", formula: "comissões e taxas próprias confirmadas", ownership: "corporativa", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
  { metric: "Carteiras", platform: "DeliGo Eats", primarySource: "deligo.legacy_wallets.available_balance", validationSource: "deligo.profiles", formula: "soma de saldos activos ligados a perfis reais", ownership: "utilizadores", currency: "MZN", eventIdentifier: "wallet_id", accountingPeriod: "updated_at" },
  { metric: "Receita de subscrições", platform: "Mestre24", primarySource: "hq.platform_financial_events.platform_fee", validationSource: "corporate_revenue_summary_v1", formula: "subscrições reconhecidas menos taxas e deduções aplicáveis", ownership: "corporativa", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
  { metric: "Receita de viagens", platform: "SARCA", primarySource: "hq.platform_financial_events.platform_fee", validationSource: "financial_transactions", formula: "comissões confirmadas de viagens", ownership: "corporativa", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
  { metric: "Receita de subscrições", platform: "Comunhão", primarySource: "hq.platform_financial_events.platform_fee", validationSource: "financial_transactions", formula: "subscrições comerciais reconhecidas", ownership: "corporativa", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
  { metric: "GMV e comissões", platform: "DeliGo Market", primarySource: "hq.platform_financial_events.gross_amount/platform_fee", validationSource: "financial_transactions", formula: "vendas e comissões confirmadas", ownership: "transacção, terceiros e corporativa", currency: "MZN", eventIdentifier: "source_record_id", accountingPeriod: "occurred_at" },
];

export type ReconciliationChecks = {
  duplicateEventIds?: number;
  unmatchedMovements?: number;
  unexpectedNegativeMinor?: number;
  stalePendingMovements?: number;
  precisionDifferenceMinor?: number;
  sourceAvailable?: boolean;
};

export function classifyChecks(checks: ReconciliationChecks): InternalReconciliationState {
  if (checks.sourceAvailable === false) return "FONTE_INSUFICIENTE";
  if ((checks.duplicateEventIds || 0) > 0 || (checks.unmatchedMovements || 0) > 0 || (checks.unexpectedNegativeMinor || 0) > 0 || (checks.precisionDifferenceMinor || 0) !== 0) return "DIVERGENTE";
  if ((checks.stalePendingMovements || 0) > 0) return "PENDENTE";
  return "RECONCILIADO_INTERNAMENTE";
}

export function sumMinorWithoutDoubleCounting(entries: Array<{ id: string; amountMinor: number; alreadyIncluded?: boolean }>) {
  const seen = new Set<string>();
  return entries.reduce((total, entry) => {
    if (entry.alreadyIncluded || seen.has(entry.id)) return total;
    seen.add(entry.id);
    return total + Math.trunc(entry.amountMinor);
  }, 0);
}
