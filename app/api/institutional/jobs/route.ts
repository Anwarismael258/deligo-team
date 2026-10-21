import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

type Job = Record<string, unknown> & { id: string; title: string; published?: boolean };
const headers = (key: string) => ({ apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", Prefer: "return=representation" });
const slugify = (value: string) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 140);
async function rest(key: string, path: string, init: RequestInit = {}) { const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, { ...init, headers: { ...headers(key), ...(init.headers || {}) }, cache: "no-store" }); if (!response.ok) throw new Error(await response.text()); return response.status === 204 ? null : response.json(); }

export async function GET() {
  const auth = await requireCorporatePermission("news.view");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!auth || !key) return NextResponse.json({ error: "Sem permissão para consultar vagas." }, { status: 403 });
  try {
    const jobs = await rest(key, "job_openings?select=*&order=updated_at.desc&limit=250") as Job[];
    return NextResponse.json({ jobs }, { headers: { "Cache-Control": "private, no-store" } });
  } catch { return NextResponse.json({ error: "Não foi possível carregar as vagas." }, { status: 502 }); }
}

export async function POST(request: NextRequest) {
  const auth = await requireCorporatePermission("news.create");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!auth || !key) return NextResponse.json({ error: "Sem permissão para criar vagas." }, { status: 403 });
  const body = await request.json() as { record?: Record<string, unknown> };
  const record = body.record || {};
  const title = String(record.title || "").trim();
  const slug = slugify(String(record.slug || title));
  if (!title || !slug || !String(record.description || "").trim()) return NextResponse.json({ error: "Título, descrição e slug são obrigatórios." }, { status: 400 });
  try {
    const job = (await rest(key, "job_openings", { method: "POST", body: JSON.stringify({ ...record, title, slug, published: false }) }))[0] as Job;
    return NextResponse.json({ job }, { status: 201 });
  } catch { return NextResponse.json({ error: "Não foi possível criar a vaga. Confirme se o slug é único." }, { status: 409 }); }
}

export async function PATCH(request: NextRequest) {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return NextResponse.json({ error: "Serviço indisponível." }, { status: 503 });
  const body = await request.json() as { id?: string; action?: "edit" | "publish" | "archive"; record?: Record<string, unknown> };
  if (!body.id) return NextResponse.json({ error: "Vaga inválida." }, { status: 400 });
  const current = ((await rest(key, `job_openings?id=eq.${encodeURIComponent(body.id)}&select=*`)) as Job[])[0];
  if (!current) return NextResponse.json({ error: "Vaga não encontrada." }, { status: 404 });
  const action = body.action || "edit";
  const permission = action === "publish" ? "news.publish" : action === "archive" ? "news.archive" : "news.edit";
  const auth = await requireCorporatePermission(permission);
  if (!auth) return NextResponse.json({ error: "Sem permissão para esta ação." }, { status: 403 });
  let changes: Record<string, unknown> = {};
  if (action === "edit") {
    const record = body.record || {};
    const title = String(record.title || current.title || "").trim();
    const slug = slugify(String(record.slug || title));
    if (!title || !slug || !String(record.description || current.description || "").trim()) return NextResponse.json({ error: "Título, descrição e slug são obrigatórios." }, { status: 400 });
    changes = { ...record, title, slug, published: Boolean(current.published) };
  }
  if (action === "publish") changes = { published: true };
  if (action === "archive") changes = { published: false };
  try { const job = (await rest(key, `job_openings?id=eq.${encodeURIComponent(body.id)}`, { method: "PATCH", body: JSON.stringify(changes) }))[0] as Job; return NextResponse.json({ job }); }
  catch { return NextResponse.json({ error: "Não foi possível guardar a vaga." }, { status: 409 }); }
}
