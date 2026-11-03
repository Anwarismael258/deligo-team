import { NextRequest, NextResponse } from "next/server";
import { createHmac } from "node:crypto";
import { hqRest, hqServiceKey } from "@/lib/hq-server";

function digest(payload: Record<string, unknown>) {
  const secret = process.env.DELIGO_DOCUMENT_SIGNING_SECRET?.trim() || hqServiceKey();
  if (!secret) throw new Error("DOCUMENT_SIGNING_SECRET_NOT_CONFIGURED");
  return createHmac("sha256", secret).update(JSON.stringify(payload)).digest("hex");
}

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code")?.trim();
  if (!code) return NextResponse.json({ verified: false, error: "Código de verificação não indicado." }, { status: 400 });
  try {
    const documents = await hqRest(`worker_official_documents?verification_code=eq.${encodeURIComponent(code)}&select=id,employee_id,terms_version_id,verification_code,integrity_hash,canonical_payload,generated_at`) as Array<Record<string, unknown>>;
    const document = documents[0];
    if (!document) return NextResponse.json({ verified: false, error: "Documento não encontrado." }, { status: 404 });
    const payload = document.canonical_payload as Record<string, unknown>;
    const expected = digest(payload);
    const verified = expected === String(document.integrity_hash || "");
    return NextResponse.json({ verified, document: { id: document.id, code: document.verification_code, employee_code: payload.employee_code, employee_name: payload.employee_name, terms_version: payload.terms_version, accepted_at: payload.accepted_at, generated_at: document.generated_at } }, { status: verified ? 200 : 409, headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("WORKER_TERMS_VERIFY_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ verified: false, error: "Não foi possível verificar o documento." }, { status: 503 });
  }
}
