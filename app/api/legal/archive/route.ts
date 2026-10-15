import { NextResponse } from "next/server";
import { requireCorporatePermission, supabaseUrl } from "@/lib/hq-server";

const folders = ["societario", "registos-fiscais", "identificacao", "pagamentos", "outros"] as const;
const labels: Record<string, string> = { societario: "Societário", "registos-fiscais": "Registos e fiscais", identificacao: "Identificação", pagamentos: "Pagamentos", outros: "Outros" };

export async function GET() {
  const auth = await requireCorporatePermission("legal.viewContracts");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!auth || !key) return NextResponse.json({ error: "Sem permissão para consultar o arquivo legal." }, { status: 403 });
  const objects: Array<Record<string, unknown>> = [];
  for (const folder of folders) {
    const response = await fetch(`${supabaseUrl()}/storage/v1/object/list/hq-legal-documents`, { method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ prefix: folder, limit: 1000, sortBy: { column: "name", order: "asc" } }), cache: "no-store" });
    if (!response.ok) continue;
    const rows = await response.json() as Array<Record<string, unknown>>;
    rows.filter((row) => row.id).forEach((row) => objects.push({ name: row.name, folder, category: labels[folder], size: row.metadata && typeof row.metadata === "object" ? (row.metadata as Record<string, unknown>).size : null, updated_at: row.updated_at || null }));
  }
  return NextResponse.json({ bucket: "hq-legal-documents", documents: objects }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(request: Request) {
  const auth = await requireCorporatePermission("legal.viewContracts");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const body = await request.json().catch(() => ({})) as { folder?: string; name?: string };
  if (!auth || !key || !folders.includes(body.folder as typeof folders[number]) || !body.name || body.name.includes("..") || body.name.includes("/")) return NextResponse.json({ error: "Pedido de ficheiro inválido." }, { status: 400 });
  const response = await fetch(`${supabaseUrl()}/storage/v1/object/sign/hq-legal-documents/${encodeURIComponent(body.folder!)}/${encodeURIComponent(body.name)}`, { method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ expiresIn: 300 }), cache: "no-store" });
  if (!response.ok) return NextResponse.json({ error: "Não foi possível preparar o download." }, { status: 404 });
  const result = await response.json() as { signedURL?: string };
  return NextResponse.json({ url: result.signedURL ? `${supabaseUrl()}/storage/v1${result.signedURL}` : null });
}
