export type DilActionLevel = "read" | "prepare" | "execute";
export type DilRequestSource = "central_web" | "support" | "mobile" | "api" | "scheduled";
export type DilDataClass = "operational_aggregate" | "workflow" | "personal_restricted" | "financial_restricted";

export type DilScope = {
  platformSlugs: string[];
  departmentCodes: string[];
  maxRows: number;
  page: number;
};

export type DilRequestContext = {
  authUserId: string;
  employeeId: string;
  roleCode: string;
  departmentCode?: string;
  sessionId?: string;
  requestSource: DilRequestSource;
  scope: DilScope;
};

export type DilToolCode =
  | "get_company_summary"
  | "get_pending_approvals"
  | "get_pending_kyc"
  | "get_finance_summary";

export type DilToolRequest<TArgs extends Record<string, unknown> = Record<string, unknown>> = {
  tool: DilToolCode;
  args: TArgs;
  actionLevel: "read";
};

export type DilToolResult<T = unknown> = {
  tool: DilToolCode;
  data: T;
  truncated: boolean;
  nextPage?: number;
  generatedAt: string;
};

export const DIL_FORBIDDEN_ACTIONS = [
  "approve_kyc", "reject_kyc", "transfer_funds", "withdraw_funds", "change_wallet",
  "suspend_account", "delete_user", "change_role", "change_permissions",
  "approve_payroll", "approve_expense", "publish_sensitive_document",
] as const;
