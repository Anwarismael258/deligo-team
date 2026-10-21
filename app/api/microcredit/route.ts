import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest, supabaseUrl } from "@/lib/hq-server";

const staff = new Set(["SUPER_ADMIN", "FINANCE"]);
const pageSize = 40;
const columns = "id,reference,full_name,bi_number,nuit,phone,wallet,email,employer,monthly_income,salary_day,amount,total_due,term_days,purpose,status,doc_folder,bi_front_path,bi_back_path,income_path,created_at,status_updated_at,status_updated_by";
const intakeActions: Record<string, string[]> = {
  pendente: ["em_analise", "recusado", "cancelado"],
  em_analise: ["recusado", "cancelado"],
};

async function actor() {
  const current = await corporateActor();
  return current && staff.has(current.role) ? current : null;
}

async function signedDocument(path: unknown, folder: unknown) {
  if (typeof path !== "string" || !path.trim() || typeof folder !== "string" || !folder.trim()) return null;
  const cleanFolder = folder.trim().replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  const cleanPath = path.trim().replace(/\\/g, "/");
  if (!cleanFolder || !cleanPath.startsWith(`${cleanFolder}/`) || cleanPath.includes("..") || cleanPath.includes("://")) return null;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  const response = await fetch(`${supabaseUrl()}/storage/v1/object/sign/loan-documents/${cleanPath.split("/").map(encodeURIComponent).join("/")}`, {
    method: "POST",
    headers: { apikey: key, Authorization: key.startsWith("sb_secret_") ? `Bearer ${key}` : `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: 300 }),
    cache: "no-store",
  });
  if (!response.ok) return null;
  const body = await response.json() as { signedURL?: string };
  if (!body.signedURL) return null;
  return body.signedURL.startsWith("http") ? body.signedURL : `${supabaseUrl()}${body.signedURL}`;
}

export async function GET(request: NextRequest) {
  const current = await actor();
  if (!current) return NextResponse.json({ error: "Sem acesso aos pedidos de microcrédito." }, { status: 403 });
  const status = request.nextUrl.searchParams.get("status");
  const page = Math.max(0, Number.parseInt(request.nextUrl.searchParams.get("page") || "0", 10) || 0);
  const search = (request.nextUrl.searchParams.get("q") || "").replace(/[^\p{L}\p{N} +\-]/gu, "").trim().slice(0, 120);
  const query = new URLSearchParams({ select: columns, order: "created_at.desc,id", limit: String(pageSize), offset: String(page * pageSize) });
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
  const body = await request.json() as { id?: string; status?: string; note?: string };
  if (!body.id) return NextResponse.json({ error: "Pedido inválido." }, { status: 400 });
  if (body.note !== undefined && (body.note.trim().length < 1 || body.note.trim().length > 2000)) return NextResponse.json({ error: "A nota deve ter entre 1 e 2000 caracteres." }, { status: 400 });
  try {
    let application: Record<string, unknown> | undefined;
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
    }
    if (body.note?.trim()) await stagingRest("loan_application_notes", { method: "POST", body: JSON.stringify({ application_id: body.id, body: body.note.trim(), author_id: current.authUserId }) });
    return NextResponse.json({ application });
  } catch {
    return NextResponse.json({ error: "Não foi possível guardar a alteração." }, { status: 409 });
  }
}
