import { NextRequest, NextResponse } from "next/server";
import { corporateActor, stagingRest } from "@/lib/hq-server";

const staff = new Set(["SUPER_ADMIN", "FINANCE"]);
const columns = "id,reference,full_name,bi_number,nuit,phone,wallet,email,employer,monthly_income,salary_day,amount,total_due,term_days,purpose,status,bi_front_path,bi_back_path,income_path,created_at,status_updated_at,status_updated_by";

async function actor() {
  const current = await corporateActor();
  return current && staff.has(current.role) ? current : null;
}

export async function GET(request: NextRequest) {
  const current = await actor();
  if (!current) return NextResponse.json({ error: "Sem acesso aos pedidos de microcrédito." }, { status: 403 });
  const status = request.nextUrl.searchParams.get("status");
  const query = new URLSearchParams({ select: columns, order: "created_at.desc", limit: "500" });
  if (status && status !== "todos") query.set("status", `eq.${status}`);
  try {
    const [applications, notes] = await Promise.all([
      stagingRest(`loan_applications?${query.toString()}`),
      stagingRest("loan_application_notes?select=id,application_id,body,created_at,author_id&order=created_at.desc&limit=500"),
    ]);
    return NextResponse.json({ applications, notes });
  } catch {
    return NextResponse.json({ error: "Não foi possível carregar os pedidos. Confirme a migração do microcrédito." }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  const current = await actor();
  if (!current) return NextResponse.json({ error: "Sem acesso." }, { status: 403 });
  const body = await request.json() as { id?: string; status?: string; note?: string };
  if (!body.id) return NextResponse.json({ error: "Pedido inválido." }, { status: 400 });
  try {
    let application;
    if (body.status) {
      const rows = await stagingRest(`loan_applications?id=eq.${encodeURIComponent(body.id)}`, {
        method: "PATCH",
        body: JSON.stringify({ status: body.status }),
      }) as unknown[];
      application = rows?.[0];
    }
    if (body.note?.trim()) await stagingRest("loan_application_notes", { method: "POST", body: JSON.stringify({ application_id: body.id, body: body.note.trim(), author_id: current.authUserId }) });
    return NextResponse.json({ application });
  } catch {
    return NextResponse.json({ error: "Não foi possível guardar a alteração." }, { status: 409 });
  }
}
