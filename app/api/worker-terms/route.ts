import { NextRequest, NextResponse } from "next/server";
import { createHmac, randomBytes } from "node:crypto";
import { corporateActor, hqRest, hqRpc, hqServiceKey, requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";
import { reportPdf } from "@/lib/report-export";

type TermsVersion = {
  id: string;
  version: string;
  title: string;
  body: { intro?: string; sections?: Array<{ title: string; text: string }> };
  content_hash: string;
  status: string;
  legal_reviewed_at?: string | null;
  effective_at?: string | null;
};

function signingSecret() {
  const value = process.env.DELIGO_DOCUMENT_SIGNING_SECRET?.trim() || hqServiceKey();
  if (!value) throw new Error("DOCUMENT_SIGNING_SECRET_NOT_CONFIGURED");
  return value;
}

function digest(payload: Record<string, unknown>) {
  return createHmac("sha256", signingSecret()).update(JSON.stringify(payload)).digest("hex");
}

function verificationCode() {
  return `DLG-TERMS-${randomBytes(6).toString("hex").toUpperCase()}`;
}

function clientIp(request: NextRequest) {
  return request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || request.headers.get("x-real-ip") || null;
}

async function employeeFor(actorId: string) {
  const rows = await hqRest(`employees?id=eq.${encodeURIComponent(actorId)}&select=id,employee_code,display_name,name,phone_e164,status` ) as Array<Record<string, unknown>>;
  return rows?.[0] || null;
}

const grandfatheredRoles = new Set(["SUPER_ADMIN", "FINANCE"]);

async function activateInvitedEmployee(actor: NonNullable<Awaited<ReturnType<typeof corporateActor>>>) {
  if (actor.status !== "invited") return false;
  const updated = await hqRest(`employees?id=eq.${encodeURIComponent(actor.employee_id)}&status=eq.invited`, {
    method: "PATCH",
    body: JSON.stringify({ status: "active", joined_on: new Date().toISOString().slice(0, 10), last_login_at: new Date().toISOString(), updated_at: new Date().toISOString() }),
  }) as Array<Record<string, unknown>>;
  if (!updated?.[0]) throw new Error("WORKER_ACTIVATION_FAILED");
  await hqRest("employee_access_history", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, actor_employee_id: actor.employee_id, event_type: "terms_accepted_account_activated", previous_status: "invited", new_status: "active", reason: "Conta activada após aceitação expressa dos termos", metadata: { activation_basis: "worker_terms_acceptance" } }) });
  return true;
}

async function markExistingActiveWorkerAsRead(actor: Awaited<ReturnType<typeof corporateActor>>, version: TermsVersion, employee: Record<string, unknown>) {
  if (!actor || actor.status !== "active" || !grandfatheredRoles.has(actor.role)) return null;
  const existing = await hqRest(`worker_terms_acceptances?employee_id=eq.${encodeURIComponent(actor.employee_id)}&terms_version_id=eq.${encodeURIComponent(version.id)}&select=*`) as Array<Record<string, unknown>>;
  if (existing[0]) return existing[0];

  const acceptedAt = new Date().toISOString();
  const acceptanceText = "Registo administrativo de leitura para trabalhador activo (CEO/Administrador ou Finanças); não substitui a aceitação expressa exigida para novas admissões.";
  const acceptancePayload = { employee_id: actor.employee_id, terms_version_id: version.id, acceptance_text: acceptanceText, accepted_at: acceptedAt, basis: "active_worker_grandfathering" };
  const acceptanceHash = digest(acceptancePayload);
  const acceptance = await hqRpc("record_worker_terms_acceptance_v1", { p_employee_id: actor.employee_id, p_terms_version_id: version.id, p_acceptance_text: acceptanceText, p_acceptance_hash: acceptanceHash, p_ip_address: null, p_user_agent: "hq-active-worker-terms-read" }, "hq") as Record<string, unknown>;
  const documents = await hqRest(`worker_official_documents?employee_id=eq.${encodeURIComponent(actor.employee_id)}&terms_version_id=eq.${encodeURIComponent(version.id)}&select=*`) as Array<Record<string, unknown>>;
  if (!documents[0]) {
    const acceptedTimestamp = String(acceptance.accepted_at || acceptedAt);
    const canonicalPayload = { document_kind: "worker_terms", employee_id: actor.employee_id, employee_code: employee.employee_code, employee_name: employee.display_name || employee.name || actor.name, terms_version: version.version, terms_content_hash: version.content_hash, acceptance_id: acceptance.id, accepted_at: acceptedTimestamp, basis: "active_worker_grandfathering" };
    const integrityHash = digest(canonicalPayload);
    await hqRest("worker_official_documents", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, terms_version_id: version.id, acceptance_id: acceptance.id, document_kind: "worker_terms", verification_code: verificationCode(), integrity_hash: integrityHash, canonical_payload: canonicalPayload }) });
  }
  await hqRest("employee_access_history", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, actor_employee_id: actor.employee_id, event_type: "terms_read_grandfathered", reason: "Trabalhador activo CEO/Administrador ou Finanças dispensado de nova aceitação", metadata: { terms_version_id: version.id, basis: "active_worker_grandfathering" } }) }).catch(() => undefined);
  return acceptance;
}

export async function GET() {
  const actor = await corporateActor({ allowInvited: true });
  if (!actor) return NextResponse.json({ error: "Sessão da Central inválida." }, { status: 401 });
  try {
    const versions = await hqRest("worker_terms_versions?select=id,version,title,body,content_hash,status,legal_reviewed_at,effective_at&order=created_at.desc") as TermsVersion[];
    const employee = await employeeFor(actor.employee_id);
    const currentVersionId = versions[0]?.id || "";
    const existingAcceptance = currentVersionId ? await hqRest(`worker_terms_acceptances?employee_id=eq.${encodeURIComponent(actor.employee_id)}&terms_version_id=eq.${encodeURIComponent(currentVersionId)}&select=*`) as Array<Record<string, unknown>> : [];
    if (versions[0]?.status === "active" && employee && !existingAcceptance[0]) await markExistingActiveWorkerAsRead(actor, versions[0], employee);
    if (existingAcceptance[0] && actor.status === "invited") await activateInvitedEmployee(actor);
    const acceptances = await hqRest(`worker_terms_acceptances?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=id,terms_version_id,accepted_at,acceptance_hash,acceptance_text`) as Array<Record<string, unknown>>;
    const documents = await hqRest(`worker_official_documents?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=id,terms_version_id,document_kind,verification_code,integrity_hash,generated_at&order=generated_at.desc`) as Array<Record<string, unknown>>;
    return NextResponse.json({ employee: { id: actor.employee_id, code: actor.employee_code, name: actor.name }, current: versions[0] || null, versions, acceptances, documents }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("WORKER_TERMS_READ_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível carregar os termos do trabalhador." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => ({})) as { action?: string; termsVersionId?: string; accepted?: boolean; acceptanceText?: string };
  const actor = await corporateActor({ allowInvited: true });
  if (!actor) return NextResponse.json({ error: "Sessão da Central inválida." }, { status: 401 });

  if (body.action === "publish") {
    const authorization = await requireCorporatePermission("settings.manage");
    if (!authorization?.isSuperAdmin) return NextResponse.json({ error: "Apenas o CEO pode publicar uma versão após revisão jurídica." }, { status: 403 });
    if (!body.termsVersionId) return NextResponse.json({ error: "Versão de termos não indicada." }, { status: 400 });
    const serviceKey = hqServiceKey();
    if (!serviceKey) return NextResponse.json({ error: "Configuração segura indisponível." }, { status: 503 });
    const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json", "Accept-Profile": "hq", "Content-Profile": "hq", Prefer: "return=representation" };
    const response = await fetch(`${supabaseUrl()}/rest/v1/worker_terms_versions?id=eq.${encodeURIComponent(body.termsVersionId)}`, { method: "PATCH", headers, body: JSON.stringify({ status: "active", legal_reviewed_at: new Date().toISOString(), effective_at: new Date().toISOString() }) });
    if (!response.ok) return NextResponse.json({ error: "Não foi possível publicar os termos." }, { status: 400 });
    await hqRest("employee_access_history", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, actor_employee_id: actor.employee_id, event_type: "terms_version_published", reason: "Publicação após revisão jurídica", metadata: { terms_version_id: body.termsVersionId } }) }).catch(() => undefined);
    return NextResponse.json({ ok: true });
  }

  if (body.accepted !== true || !body.termsVersionId || !body.acceptanceText?.trim()) return NextResponse.json({ error: "A confirmação expressa e a versão dos termos são obrigatórias." }, { status: 400 });
  const employee = await employeeFor(actor.employee_id);
  if (!employee) return NextResponse.json({ error: "Trabalhador não encontrado." }, { status: 404 });
  try {
    const versions = await hqRest(`worker_terms_versions?id=eq.${encodeURIComponent(body.termsVersionId)}&select=id,version,title,body,content_hash,status,effective_at`) as TermsVersion[];
    const version = versions[0];
    if (!version || version.status !== "active") return NextResponse.json({ error: "Esta versão ainda aguarda validação e publicação jurídica." }, { status: 409 });
    const acceptedAt = new Date().toISOString();
    const acceptancePayload = { employee_id: actor.employee_id, terms_version_id: version.id, acceptance_text: body.acceptanceText.trim(), accepted_at: acceptedAt };
    const acceptanceHash = digest(acceptancePayload);
    const acceptance = await hqRpc("record_worker_terms_acceptance_v1", { p_employee_id: actor.employee_id, p_terms_version_id: version.id, p_acceptance_text: body.acceptanceText.trim(), p_acceptance_hash: acceptanceHash, p_ip_address: clientIp(request), p_user_agent: request.headers.get("user-agent") || null }, "hq") as Record<string, unknown>;
    const existing = await hqRest(`worker_official_documents?employee_id=eq.${encodeURIComponent(actor.employee_id)}&terms_version_id=eq.${encodeURIComponent(version.id)}&select=*`) as Array<Record<string, unknown>>;
    if (existing[0]) {
      const activated = await activateInvitedEmployee(actor);
      return NextResponse.json({ ok: true, acceptance, document: existing[0], accountStatus: activated ? "active" : actor.status });
    }
    const acceptedTimestamp = String(acceptance.accepted_at || acceptedAt);
    const canonicalPayload = { document_kind: "worker_terms", employee_id: actor.employee_id, employee_code: employee.employee_code, employee_name: employee.display_name || employee.name || actor.name, terms_version: version.version, terms_content_hash: version.content_hash, acceptance_id: acceptance.id, accepted_at: acceptedTimestamp };
    const integrityHash = digest(canonicalPayload);
    const document = await hqRest("worker_official_documents", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, terms_version_id: version.id, acceptance_id: acceptance.id, document_kind: "worker_terms", verification_code: verificationCode(), integrity_hash: integrityHash, canonical_payload: canonicalPayload }) });
    await hqRest("employee_access_history", { method: "POST", body: JSON.stringify({ employee_id: actor.employee_id, actor_employee_id: actor.employee_id, event_type: "terms_accepted", reason: "Confirmação expressa do trabalhador", metadata: { terms_version_id: version.id, document_id: Array.isArray(document) ? document[0]?.id : document?.id } }) }).catch(() => undefined);
    const activated = await activateInvitedEmployee(actor);
    return NextResponse.json({ ok: true, acceptance, document: Array.isArray(document) ? document[0] : document, accountStatus: activated ? "active" : actor.status });
  } catch (error) {
    console.error("WORKER_TERMS_ACCEPT_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível registar a aceitação expressa." }, { status: 503 });
  }
}

export async function PUT(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor) return NextResponse.json({ error: "Sessão da Central inválida." }, { status: 401 });
  const body = await request.json().catch(() => ({})) as { documentId?: string };
  if (!body.documentId) return NextResponse.json({ error: "Documento não indicado." }, { status: 400 });
  const docs = await hqRest(`worker_official_documents?id=eq.${encodeURIComponent(body.documentId)}&employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=id,employee_id,terms_version_id,verification_code,integrity_hash,canonical_payload,generated_at`) as Array<Record<string, unknown>>;
  const document = docs[0];
  if (!document) return NextResponse.json({ error: "Documento não encontrado." }, { status: 404 });
  const versions = await hqRest(`worker_terms_versions?id=eq.${encodeURIComponent(String(document.terms_version_id))}&select=version,title,body,content_hash`) as TermsVersion[];
  const employee = await employeeFor(actor.employee_id);
  const bodyData = versions[0]?.body || {};
  const lines = ["DELIIGO TRIUNFAL, LDA.", "TERMOS DE TRABALHO E UTILIZAÇÃO DA CENTRAL HQ", "", `Trabalhador: ${employee?.display_name || employee?.name || actor.name}`, `Código: ${employee?.employee_code || actor.employee_code}`, `Versão: ${versions[0]?.version || "—"}`, `Aceite em: ${String((document.canonical_payload as Record<string, unknown>)?.accepted_at || "—")}`, `Código de verificação: ${String(document.verification_code)}`, `Integridade HMAC-SHA256: ${String(document.integrity_hash)}`, "", "Verificação: /api/worker-terms/verify?code=" + String(document.verification_code), "", String(bodyData.intro || "")];
  for (const section of Array.isArray(bodyData.sections) ? bodyData.sections : []) lines.push("", String(section.title || ""), String(section.text || ""));
  lines.push("", "Aceitação expressa registada no sistema oficial DeliGo Triunfal.", "Este documento não substitui contrato, política interna ou aconselhamento jurídico.");
  const pdf = reportPdf(lines);
  return new NextResponse(pdf as BodyInit, { status: 200, headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="deligo-termos-${String(employee?.employee_code || actor.employee_code)}-${String(versions[0]?.version || "versao")}.pdf"`, "Cache-Control": "private, no-store" } });
}
