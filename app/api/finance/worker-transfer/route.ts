import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc } from "@/lib/hq-server";

export const dynamic = "force-dynamic";

const allowedRoles = new Set(["SUPER_ADMIN", "FINANCE"]);

export async function GET() {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) {
    return NextResponse.json({ error: "Apenas Admin ou Finanças podem transferir para trabalhadores." }, { status: 403 });
  }
  try {
    // Use the same canonical directory as the People module. The direct REST
    // query used to return an empty list when role/status are derived by the
    // directory RPC rather than physical columns on hq.employees.
    const directory = await hqRpc("hq_employee_directory_v1") as Array<Record<string, unknown>>;
    const employees = (Array.isArray(directory) ? directory : [])
      .filter((employee) => String(employee.status || "").toLowerCase() === "active" && Boolean(employee.auth_user_id))
      .filter((employee) => String(employee.id) !== String(actor.employee_id))
      .sort((left, right) => String(left.name || left.display_name || "").localeCompare(String(right.name || right.display_name || "")));
    return NextResponse.json({
      employees: employees.map((employee) => ({
        id: employee.id,
        name: employee.name || employee.display_name || "Trabalhador",
        employee_code: employee.employee_code,
        job_title: employee.job_title,
        role: employee.role,
        phone: employee.phone || employee.phone_e164,
      })),
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "Não foi possível carregar os trabalhadores activos." }, { status: 503 });
  }
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) {
    return NextResponse.json({ error: "Apenas Admin ou Finanças podem transferir para trabalhadores." }, { status: 403 });
  }
  const body = await request.json().catch(() => null) as { employeeId?: string; amount?: number; idempotencyKey?: string } | null;
  const employeeId = String(body?.employeeId || "").trim();
  const amount = Number(body?.amount);
  if (!employeeId || !Number.isFinite(amount) || amount <= 0) {
    return NextResponse.json({ error: "Escolha um trabalhador e indique um valor válido." }, { status: 400 });
  }
  const idempotencyKey = String(body?.idempotencyKey || `hq-worker-transfer-${actor.authUserId}-${crypto.randomUUID()}`).trim();
  try {
    const result = await hqRpc("hq_transfer_employee_personal_to_worker_v1", {
      p_actor_auth_user_id: actor.authUserId,
      p_target_employee_id: employeeId,
      p_amount: Math.round(amount * 100) / 100,
      p_idempotency_key: idempotencyKey,
    });
    return NextResponse.json({ result }, { status: 201 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível concluir a transferência.";
    const known = message.includes("personal_wallet_insufficient")
      ? "Saldo pessoal insuficiente para esta transferência."
      : message.includes("target_employee_not_found")
        ? "O trabalhador seleccionado não está activo ou não tem conta de acesso."
        : message.includes("target_must_be_another_worker")
          ? "Escolha outro trabalhador; não pode transferir para a própria conta."
          : message.includes("source_personal_wallet_not_found")
            ? "Não existe uma carteira pessoal activa para o utilizador actual."
          : "Não foi possível concluir a transferência. Nenhum saldo foi movimentado.";
    return NextResponse.json({ error: known }, { status: 409 });
  }
}
