import { DilToolCode } from "@/lib/dil/contracts";
import { DATA_CLASS_BY_TOOL } from "@/lib/dil/policy-engine";

export const DIL_TOOL_REGISTRY: Record<DilToolCode, { code: DilToolCode; dataClass: string; description: string }> = {
  get_company_summary: { code: "get_company_summary", dataClass: DATA_CLASS_BY_TOOL.get_company_summary, description: "Resumo operacional agregado." },
  get_pending_approvals: { code: "get_pending_approvals", dataClass: DATA_CLASS_BY_TOOL.get_pending_approvals, description: "Aprovações pendentes, sem executar decisões." },
  get_pending_kyc: { code: "get_pending_kyc", dataClass: DATA_CLASS_BY_TOOL.get_pending_kyc, description: "Casos KYC pendentes, sem documentos sensíveis." },
  get_finance_summary: { code: "get_finance_summary", dataClass: DATA_CLASS_BY_TOOL.get_finance_summary, description: "Indicadores financeiros autorizados, sem movimentação." },
};

export function isDilTool(value: unknown): value is DilToolCode { return typeof value === "string" && value in DIL_TOOL_REGISTRY; }
