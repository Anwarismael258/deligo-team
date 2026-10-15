import { hqRest } from "@/lib/hq-server";
import { DilRequestContext, DilToolCode, DilToolResult } from "@/lib/dil/contracts";

const TABLES: Record<DilToolCode, string> = {
  get_company_summary: "executive_finance_dashboard_v1",
  get_pending_approvals: "approval_requests",
  get_pending_kyc: "platform_kyc_cases",
  get_finance_summary: "executive_finance_dashboard_v1",
};

export async function executeDilTool(tool: DilToolCode, ctx: DilRequestContext): Promise<DilToolResult> {
  const limit = Math.min(100, Math.max(1, ctx.scope.maxRows));
  const offset = Math.max(0, ctx.scope.page - 1) * limit;
  const path = `${TABLES[tool]}?select=*&limit=${limit}&offset=${offset}`;
  const response = await hqRest(path, { headers: { "Accept-Profile": "hq", "Content-Profile": "hq" } });
  if (!response.ok) throw new Error(`DIL_TOOL_SOURCE_${response.status}`);
  const data = await response.json();
  const rows = Array.isArray(data) ? data.slice(0, limit) : data;
  return { tool, data: rows, truncated: Array.isArray(data) && data.length >= limit, nextPage: Array.isArray(data) && data.length >= limit ? ctx.scope.page + 1 : undefined, generatedAt: new Date().toISOString() };
}
