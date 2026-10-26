import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqServiceKey, stagingRest, supabaseUrl } from "@/lib/hq-server";
import { dispatchMicrocreditPacket } from "@/lib/microcredit-packets";

const staff = new Set(["SUPER_ADMIN", "FINANCE"]);
const pageSize = 40;
const columns = "id,reference,full_name,bi_number,nuit,phone,wallet,email,employer,monthly_income,salary_day,amount,total_due,term_days,purpose,status,doc_folder,bi_front_path,bi_back_path,income_path,created_at,status_updated_at,status_updated_by";
const intakeActions: Record<string, string[]> = {
  pendente: ["em_analise", "recusado", "cancelado"],
  em_analise: ["aprovado", "recusado", "cancelado"],
};

async function actor() {
  const current = await corporateActor();
  return current && staff.has(current.role) ? current : null;
}

async function signedDocument(path: unknown, folder: unknown) {
  if (typeof path !== "string" || !path.trim()) return null;
  const cleanFolder = typeof folder === "string" ? folder.trim().replace(/\\/g, "/").replace(/^\/+|\/+$/g, "") : "";
  let cleanPath = path.trim();
  // Older submissions stored a complete Supabase Storage URL. Keep only the
  // bucket-relative object path so we can sign it against the current private
  // project, never forward an expired token or an arbitrary bucket.
  if (/^https?:\/\//i.test(cleanPath)) {
    try {
      const parsed = new URL(cleanPath);
      const marker = "/storage/v1/object/";
      const markerIndex = parsed.pathname.indexOf(marker);
      if (markerIndex < 0) return null;
      const objectPath = parsed.pathname.slice(markerIndex + marker.length);
      const bucketIndex = objectPath.indexOf("loan-documents/");
      if (bucketIndex < 0) return null;
      cleanPath = objectPath.slice(bucketIndex + "loan-documents/".length);
    } catch {
      return null;
    }
  }
  cleanPath = cleanPath.replace(/\\/g, "/").replace(/^\/+/, "");
  if (cleanPath.startsWith("loan-documents/")) cleanPath = cleanPath.slice("loan-documents/".length);
  if (!cleanPath || cleanPath.includes("..") || cleanPath.includes("://") || cleanPath.includes("\\0")) return null;
  if (!cleanPath.includes("/") && cleanFolder) cleanPath = `${cleanFolder}/${cleanPath}`;
  if (cleanFolder && !cleanPath.startsWith(`${cleanFolder}/`)) return null;
  const key = hqServiceKey();
  if (!key) return null;
  try {
    const headers: Record<string, string> = { apikey: key, "Content-Type": "application/json" };
    if (!key.startsWith("sb_secret_")) headers.Authorization = `Bearer ${key}`;
    const response = await fetch(`${supabaseUrl()}/storage/v1/object/sign/loan-documents/${cleanPath.split("/").map(encodeURIComponent).join("/")}`, {
      method: "POST", headers, body: JSON.stringify({ expiresIn: 300 }), cache: "no-store",
    });
    if (!response.ok) return null;
    const body = await response.json() as { signedURL?: string; signedUrl?: string };
    const signed = body.signedURL || body.signedUrl;
    if (!signed) return null;
    return signed.startsWith("http") ? signed : `${supabaseUrl()}${signed}`;
  } catch {
    return null;
  }
}

export async function GET(request: NextRequest) {
  const current = await actor();
  if (!current) return NextResponse.json({ error: "Sem acesso aos pedidos de microcrédito." }, { status: 403 });
  const status = request.nextUrl.searchParams.get("status");
  const page = Math.max(0, Number.parseInt(request.nextUrl.searchParams.get("page") || "0", 10) || 0);
  const search = (request.nextUrl.searchParams.get("q") || "").replace(/[^\p{L}\p{N} +\-]/gu, "").trim().slice(0, 120);
  const query = new URLSearchParams({ select: columns, order: "created_at.desc,id.asc", limit: String(pageSize), offset: String(page * pageSize) });
  if (status && status !== "todos") query.set("status", `eq.${status}`);
  if (search) query.set("or", `(full_name.ilike.*${search}*,reference.ilike.*${search}*,phone.ilike.*${search}*,bi_number.ilike.*${search}*,nuit.ilike.*${search}*)`);
  try {
    const [applications, notes] = await Promise.all([
      stagingRest(`loan_applications?${query.toString()}`),
      stagingRest("loan_application_notes?select=id,application_id,body,created_at,author_id&order=created_at.desc&limit=500"),
    ]);
    const enrichedApplications = await Promise.all((applications as Record<string, unknown>[]).map(async application => ({
      ...application,
      documents: {
        bi_front: await signedDocument(application.bi_front_path, application.doc_folder),
        bi_back: await signedDocument(application.bi_back_path, application.doc_folder),
        income: await signedDocument(application.income_path, application.doc_folder),
      },
    })));
    return NextResponse.json({ applications: enrichedApplications, notes, page, pageSize, hasMore: (applications as unknown[]).length === pageSize });
  } catch {
    return NextResponse.json({ error: "Não foi possível carregar os pedidos. Confirme a migração do microcrédito." }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  const current = await actor();
  if (!current) return NextResponse.json({ error: "Sem acesso." }, { status: 403 });
  const body = await request.json() as { id?: string; status?: string; note?: string; resend?: boolean };
  if (!body.id) return NextResponse.json({ error: "Pedido inválido." }, { status: 400 });
  if (body.note !== undefined && (body.note.trim().length < 1 || body.note.trim().length > 2000)) return NextResponse.json({ error: "A nota deve ter entre 1 e 2000 caracteres." }, { status: 400 });
  try {
    let application: Record<string, unknown> | undefined;
    let delivery: unknown = null;
    let deliveryWarning: string | null = null;
    if (body.status) {
      const currentRows = await stagingRest(`loan_applications?id=eq.${encodeURIComponent(body.id)}&select=id,status`) as Array<Record<string, unknown>>;
      const current = currentRows?.[0];
      const currentStatus = String(current?.status || "");
      if (!current) return NextResponse.json({ error: "Pedido não encontrado." }, { status: 404 });
      if (!(intakeActions[currentStatus] || []).includes(body.status)) return NextResponse.json({ error: "Esta alteração requer o procedimento controlado da Central." }, { status: 409 });
      const rows = await stagingRest(`loan_applications?id=eq.${encodeURIComponent(body.id)}`, {
        method: "PATCH",
        body: JSON.stringify({ status: body.status }),
      }) as Array<Record<string, unknown>>;
      application = rows?.[0];
      if (!application) return NextResponse.json({ error: "O pedido mudou entretanto. Actualize antes de continuar." }, { status: 409 });
      if (body.status === "aprovado") {
        try {
          delivery = await dispatchMicrocreditPacket(application, "confirmed");
        } catch (error) {
          deliveryWarning = error instanceof Error ? error.message.split(":")[0] : "MICROCREDIT_DISPATCH_FAILED";
        }
      }
    }
    if (body.resend) {
      const rows = await stagingRest(`loan_applications?id=eq.${encodeURIComponent(body.id)}&limit=1`) as Array<Record<string, unknown>>;
      application = rows?.[0];
      if (!application || application.status !== "aprovado") return NextResponse.json({ error: "Só é possível reenviar a confirmação de um pedido aprovado." }, { status: 409 });
      try { delivery = await dispatchMicrocreditPacket(application, "confirmed"); }
      catch (error) { deliveryWarning = error instanceof Error ? error.message.split(":")[0] : "MICROCREDIT_DISPATCH_FAILED"; }
    }
    if (body.note?.trim()) await stagingRest("loan_application_notes", { method: "POST", body: JSON.stringify({ application_id: body.id, body: body.note.trim(), author_id: current.authUserId }) });
    return NextResponse.json({ application, delivery, deliveryWarning });
  } catch {
    return NextResponse.json({ error: "Não foi possível guardar a alteração." }, { status: 409 });
  }
}
