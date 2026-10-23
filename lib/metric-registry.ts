export type MetricKind = "revenue" | "wallet" | "custody" | "reconciliation" | "operational";

export type MetricDefinition = {
  key: string;
  label: string;
  kind: MetricKind;
  unit: "MZN" | "count";
  source: string;
  ownership: "corporate" | "user" | "third_party" | "gateway";
  includedInCustody: boolean;
  description: string;
};

export const metricRegistry: readonly MetricDefinition[] = [
  { key: "finance.corporate_revenue_confirmed", label: "Receita corporativa confirmada", kind: "revenue", unit: "MZN", source: "hq.corporate_revenue_credits + hq.platform_financial_events", ownership: "corporate", includedInCustody: true, description: "Comissões, taxas e receitas líquidas confirmadas; não representa automaticamente saldo PaySuite." },
  { key: "finance.user_wallets_available", label: "Carteiras de utilizadores disponíveis", kind: "wallet", unit: "MZN", source: "payments.wallet_accounts + deligo.legacy_wallets", ownership: "user", includedInCustody: true, description: "Saldos disponíveis de clientes, restaurantes, estafetas, vendedores, drivers e riders." },
  { key: "finance.corporate_wallet_available", label: "Carteira corporativa disponível", kind: "wallet", unit: "MZN", source: "hq.logical_wallets/CORPORATE_MZN", ownership: "corporate", includedInCustody: true, description: "Saldo operacional da carteira corporativa, separado das carteiras pessoais." },
  { key: "finance.custody_available", label: "Total sob custódia disponível", kind: "custody", unit: "MZN", source: "receita corporativa + carteiras de utilizadores", ownership: "third_party", includedInCustody: false, description: "Soma consolidada sem dupla contagem entre receita e carteiras." },
  { key: "finance.paysuite_balance", label: "Saldo PaySuite", kind: "reconciliation", unit: "MZN", source: "PaySuite balance API oficial", ownership: "gateway", includedInCustody: false, description: "Só deve ser preenchido por resposta autenticada da API oficial de saldo." },
  { key: "finance.reconciliation_difference", label: "Diferença de reconciliação", kind: "reconciliation", unit: "MZN", source: "PaySuite versus ledger interno", ownership: "gateway", includedInCustody: false, description: "Diferença explicada por pendentes, taxas, levantamentos ou movimentos não conciliados." },
];

export function metricDefinition(key: string) {
  return metricRegistry.find(metric => metric.key === key) || null;
}
