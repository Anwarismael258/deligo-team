import { NextRequest, NextResponse } from "next/server";
import { createHmac } from "node:crypto";
import { corporateActor, hqRest, hqServiceKey } from "@/lib/hq-server";
import { reportPdf } from "@/lib/report-export";

function verify(payload: Record<string, unknown>, hash: string) {
  const secret = process.env.DELIGO_DOCUMENT_SIGNING_SECRET?.trim() || hqServiceKey();
  if (!secret) return false;
  const expected = createHmac("sha256", secret).update(JSON.stringify(payload)).digest("hex");
  return expected === hash;
}

export async function GET(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão da Central inválida." }, { status: 401 });
  const employeeId = request.nextUrl.searchParams.get("employeeId")?.trim();
  const documentId = request.nextUrl.searchParams.get("documentId")?.trim();
  if (!employeeId && !documentId) return NextResponse.json({ error: "Indique o trabalhador ou o documento." }, { status: 400 });
  const filter = documentId ? `id=eq.${encodeURIComponent(documentId)}` : `employee_id=eq.${encodeURIComponent(employeeId || "")}`;
  const documents = await hqRest(`employee_closure_reports?${filter}&select=id,employee_id,actor_employee_id,reason,verification_code,integrity_hash,canonical_payload,generated_at&order=generated_at.desc`) as Array<Record<string, unknown>>;
  if (!documents[0]) return NextResponse.json({ error: "Nenhum relatório de encerramento encontrado." }, { status: 404 });
  const document = documents[0];
  const payload = document.canonical_payload as Record<string, unknown>;
  const valid = verify(payload, String(document.integrity_hash || ""));
  if (!valid) return NextResponse.json({ error: "A integridade do documento não pôde ser confirmada." }, { status: 409 });
  const employee = (payload.employee || {}) as Record<string, unknown>;
  const reports = (payload.reports || {}) as Record<string, unknown>;
  const lines = [
    "DELIGO TRIUNFAL, LDA.",
    "RELATÓRIO OFICIAL DE ENCERRAMENTO DO VÍNCULO",
    "",
    `Trabalhador: ${String(employee.display_name || employee.name || "—")}`,
    `Código: ${String(employee.employee_code || "—")}`,
    `Telefone: ${String(employee.phone_e164 || "—")}`,
    `Cargo: ${String(employee.job_title || "—")}`,
    `Departamento: ${String(employee.department || "—")}`,
    `Estado: ${String(employee.status || "offboarded")}`,
    `Encerrado em: ${String(employee.offboarded_at || payload.generated_at || "—")}`,
    `Motivo: ${String(document.reason || "—")}`,
    `Código de verificação: ${String(document.verification_code || "—")}`,
    `Integridade HMAC-SHA256: ${String(document.integrity_hash || "—")}`,
    "",
    "Resumo dos registos preservados",
    `Histórico de acessos: ${Array.isArray(reports.access_history) ? reports.access_history.length : 0} registos`,
    `Alterações administrativas: ${Array.isArray(reports.change_history) ? reports.change_history.length : 0} registos`,
    `Processos laborais: ${Array.isArray(reports.workforce_requests) ? reports.workforce_requests.length : 0} registos`,
    "",
    "Este documento foi gerado pelo sistema oficial da DeliGo Triunfal. A validade pode ser confirmada pelo código e pela integridade apresentados.",
  ];
  for (const [label, value] of [["Acessos", reports.access_history], ["Alterações", reports.change_history], ["Processos laborais", reports.workforce_requests]] as Array<[string, unknown]>) {
    if (!Array.isArray(value)) continue;
    lines.push("", label);
    for (const row of value) {
      const item = row as Record<string, unknown>;
      lines.push(`- ${String(item.event_type || item.action || item.request_type || "Registo")} · ${String(item.occurred_at || item.created_at || "—")} · ${String(item.reason || item.status || "")}`);
    }
  }
  const pdf = reportPdf(lines);
  return new NextResponse(pdf as BodyInit, { status: 200, headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="deligo-encerramento-${String(employee.employee_code || document.employee_id)}.pdf"`, "Cache-Control": "private, no-store" } });
}
