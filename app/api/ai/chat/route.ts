import { NextResponse } from "next/server";
import { corporateAuthorization } from "@/lib/hq-server";
import { DilRequestSource, DilToolCode } from "@/lib/dil/contracts";
import { auditDilEvent } from "@/lib/dil/audit";
import { enforcePolicy } from "@/lib/dil/policy-engine";
import { executeDilTool } from "@/lib/dil/tool-executor";
import { isDilTool } from "@/lib/dil/tool-registry";

export async function POST(request: Request) {
  const started = Date.now(); let body: Record<string, unknown> = {};
  try { body = await request.json(); } catch { return NextResponse.json({ error: "INVALID_JSON" }, { status: 400 }); }
  const question = typeof body.question === "string" ? body.question : "";
  const tool = body.tool as DilToolCode;
  const source = (typeof body.requestSource === "string" ? body.requestSource : "central_web") as DilRequestSource;
  const auth = await corporateAuthorization().catch(() => null);
  const baseEvent = { question, tool, request_source: source, created_at: new Date().toISOString() };
  if (!auth) { await auditDilEvent({ ...baseEvent, status: "denied", code: "UNAUTHENTICATED" }); return NextResponse.json({ error: "UNAUTHENTICATED" }, { status: 401 }); }
  if (!isDilTool(tool)) { await auditDilEvent({ ...baseEvent, employee_id: auth.actor.employee_id, status: "denied", code: "UNKNOWN_TOOL" }); return NextResponse.json({ error: "UNKNOWN_TOOL" }, { status: 400 }); }
  const ctx = { authUserId: auth.actor.authUserId, employeeId: auth.actor.employee_id, roleCode: auth.actor.role, requestSource: source, scope: { platformSlugs: auth.platformSlugs, departmentCodes: [], maxRows: Math.min(Number(body.maxRows) || 25, 100), page: Math.max(Number(body.page) || 1, 1) } };
  const requestedPlatform = typeof body.platformSlug === "string" ? body.platformSlug : undefined;
  if (requestedPlatform && !auth.isSuperAdmin && !auth.platformSlugs.includes(requestedPlatform)) {
    await auditDilEvent({ ...baseEvent, employee_id: ctx.employeeId, status: "denied", code: "PLATFORM_SCOPE_BLOCKED", requested_platform: requestedPlatform, latency_ms: Date.now() - started });
    return NextResponse.json({ error: "PLATFORM_SCOPE_BLOCKED" }, { status: 403 });
  }
  if (requestedPlatform) ctx.scope.platformSlugs = [requestedPlatform];
  const decision = enforcePolicy(ctx, tool, "read", question);
  if (!decision.allowed) { await auditDilEvent({ ...baseEvent, employee_id: ctx.employeeId, status: "denied", code: decision.code, latency_ms: Date.now() - started }); return NextResponse.json({ error: decision.code, message: decision.reason }, { status: 403 }); }
  try { const result = await executeDilTool(tool, ctx); await auditDilEvent({ ...baseEvent, employee_id: ctx.employeeId, status: "success", data_class: tool, latency_ms: Date.now() - started }); return NextResponse.json({ ok: true, model: null, result, audit: "recorded_or_logged" }); }
  catch (error) { await auditDilEvent({ ...baseEvent, employee_id: ctx.employeeId, status: "error", code: "TOOL_EXECUTION_FAILED", error: String(error), latency_ms: Date.now() - started }); return NextResponse.json({ error: "TOOL_EXECUTION_FAILED" }, { status: 503 }); }
}
