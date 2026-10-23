export type MetricKind = "revenue" | "wallet" | "custody" | "reconciliation" | "operational";

export type MetricDefinition = {
  key: string;
  label: string;
  kind: MetricKind;
  unit: "MZN" | "count";
  formula: string;
  source: string;
  periodicity: "realtime" | "daily" | "monthly" | "on_demand";
  permissions: string[];
  version: number;
  ownership: "corporate" | "user" | "third_party" | "gateway";
  includedInCustody: boolean;
  description: string;
};

export const metricRegistry: readonly MetricDefinition[] = [
  { key: "finance.corporate_revenue_confirmed", label: "Receita corporativa confirmada", kind: "revenue", unit: "MZN", formula: "comissões + taxas próprias + subscrições reconhecidas - deduções aplicáveis", source: "hq.corporate_revenue_credits + hq.platform_financial_events", periodicity: "on_demand", permissions: ["finance.view"], version: 1, ownership: "corporate", includedInCustody: true, description: "Comissões, taxas e receitas líquidas confirmadas; não representa automaticamente saldo PaySuite." },
  { key: "finance.user_wallets_available", label: "Carteiras de utilizadores disponíveis", kind: "wallet", unit: "MZN", formula: "soma dos saldos disponíveis de carteiras elegíveis, sem carteiras pessoais HQ", source: "payments.wallet_accounts + deligo.legacy_wallets", periodicity: "realtime", permissions: ["finance.view"], version: 1, ownership: "user", includedInCustody: true, description: "Saldos disponíveis de clientes, restaurantes, estafetas, vendedores, drivers e riders." },
  { key: "finance.corporate_wallet_available", label: "Carteira corporativa disponível", kind: "wallet", unit: "MZN", formula: "saldo disponível da carteira corporativa canónica", source: "hq.logical_wallets/CORPORATE_MZN", periodicity: "realtime", permissions: ["finance.view"], version: 1, ownership: "corporate", includedInCustody: true, description: "Saldo operacional da carteira corporativa, separado das carteiras pessoais." },
  { key: "finance.custody_available", label: "Total sob custódia disponível", kind: "custody", unit: "MZN", formula: "receita corporativa disponível + carteiras de utilizadores elegíveis", source: "receita corporativa + carteiras de utilizadores", periodicity: "realtime", permissions: ["finance.view"], version: 1, ownership: "third_party", includedInCustody: false, description: "Soma consolidada sem dupla contagem entre receita e carteiras." },
  { key: "finance.paysuite_balance", label: "Saldo PaySuite", kind: "reconciliation", unit: "MZN", formula: "saldo confirmado devolvido pela API oficial PaySuite", source: "PaySuite balance API oficial", periodicity: "on_demand", permissions: ["finance.reconcile"], version: 1, ownership: "gateway", includedInCustody: false, description: "Só deve ser preenchido por resposta autenticada da API oficial de saldo." },
  { key: "finance.reconciliation_difference", label: "Diferença de reconciliação", kind: "reconciliation", unit: "MZN", formula: "saldo PaySuite confirmado - saldo esperado do ledger", source: "PaySuite versus ledger interno", periodicity: "on_demand", permissions: ["finance.reconcile"], version: 1, ownership: "gateway", includedInCustody: false, description: "Diferença explicada por pendentes, taxas, levantamentos ou movimentos não conciliados." },
];

export function metricDefinition(key: string) {
  return metricRegistry.find(metric => metric.key === key) || null;
}
