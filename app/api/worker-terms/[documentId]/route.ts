import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRest } from "@/lib/hq-server";
import { reportPdf } from "@/lib/report-export";

export async function GET(_request: NextRequest, context: { params: Promise<{ documentId: string }> }) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão da Central inválida." }, { status: 401 });
  const { documentId } = await context.params;
  const docs = await hqRest(`worker_official_documents?id=eq.${encodeURIComponent(documentId)}&employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=id,employee_id,terms_version_id,verification_code,integrity_hash,canonical_payload,generated_at`) as Array<Record<string, unknown>>;
  const document = docs[0];
  if (!document) return NextResponse.json({ error: "Documento não encontrado." }, { status: 404 });
  const versions = await hqRest(`worker_terms_versions?id=eq.${encodeURIComponent(String(document.terms_version_id))}&select=version,title,body,content_hash`) as Array<{ version?: string; title?: string; body?: { intro?: string; sections?: Array<{ title: string; text: string }> } }>;
  const employees = await hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&select=employee_code,display_name,name`) as Array<Record<string, unknown>>;
  const employee = employees[0] || {};
  const version = versions[0] || {};
  const body = version.body || {};
  const payload = document.canonical_payload as Record<string, unknown>;
  const lines = ["DELIIGO TRIUNFAL, LDA.", "TERMOS DE TRABALHO E UTILIZAÇÃO DA CENTRAL HQ", "", `Trabalhador: ${employee.display_name || employee.name || actor.name}`, `Código: ${employee.employee_code || actor.employee_code}`, `Versão: ${version.version || "—"}`, `Aceite em: ${payload.accepted_at || "—"}`, `Código de verificação: ${document.verification_code}`, `Integridade HMAC-SHA256: ${document.integrity_hash}`, "", "Verificação: /api/worker-terms/verify?code=" + String(document.verification_code), "", String(body.intro || "")];
  for (const section of Array.isArray(body.sections) ? body.sections : []) lines.push("", String(section.title || ""), String(section.text || ""));
  lines.push("", "Aceitação expressa registada no sistema oficial DeliGo Triunfal.", "Este documento não substitui contrato, política interna ou aconselhamento jurídico.");
  const pdf = reportPdf(lines);
  return new NextResponse(pdf as BodyInit, { status: 200, headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="deligo-termos-${String(employee.employee_code || actor.employee_code)}-${String(version.version || "versao")}.pdf"`, "Cache-Control": "private, no-store" } });
}
