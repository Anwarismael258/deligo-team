import { DIL_FORBIDDEN_ACTIONS, DilActionLevel, DilDataClass, DilRequestContext, DilToolCode } from "@/lib/dil/contracts";

export type PolicyDecision = { allowed: true } | { allowed: false; code: string; reason: string };

const ROLE_ACCESS: Record<DilToolCode, string[]> = {
  get_company_summary: ["CEO", "SUPER_ADMIN", "ADMIN", "OPERATIONS"],
  get_pending_approvals: ["CEO", "SUPER_ADMIN", "ADMIN", "FINANCE", "FINANCE_DIRECTOR"],
  get_pending_kyc: ["CEO", "SUPER_ADMIN", "ADMIN", "COMPLIANCE", "OPERATIONS"],
  get_finance_summary: ["CEO", "SUPER_ADMIN", "ADMIN", "FINANCE", "FINANCE_DIRECTOR", "ACCOUNTING"],
};

export function enforcePolicy(ctx: DilRequestContext, tool: DilToolCode, actionLevel: DilActionLevel, text: string): PolicyDecision {
  const normalized = text.toLowerCase();
  if (DIL_FORBIDDEN_ACTIONS.some((action) => normalized.includes(action))) return { allowed: false, code: "FORBIDDEN_ACTION", reason: "Ação sensível bloqueada na Fase 1." };
  if (actionLevel !== "read") return { allowed: false, code: "ACTION_LEVEL_BLOCKED", reason: "A Fase 1 permite apenas leitura." };
  if (!ROLE_ACCESS[tool]?.includes(ctx.roleCode.toUpperCase())) return { allowed: false, code: "TOOL_NOT_PERMITTED", reason: "O cargo não tem permissão para esta ferramenta." };
  if (ctx.scope.maxRows < 1 || ctx.scope.maxRows > 100) return { allowed: false, code: "SCOPE_INVALID", reason: "Limite de linhas inválido." };
  if (/(ignore|bypass|mostre todas|password|senha|outra plataforma)/i.test(text)) return { allowed: false, code: "PROMPT_POLICY_BLOCKED", reason: "Pedido incompatível com o escopo autorizado." };
  return { allowed: true };
}

export const DATA_CLASS_BY_TOOL: Record<DilToolCode, DilDataClass> = {
  get_company_summary: "operational_aggregate",
  get_pending_approvals: "workflow",
  get_pending_kyc: "personal_restricted",
  get_finance_summary: "financial_restricted",
};
