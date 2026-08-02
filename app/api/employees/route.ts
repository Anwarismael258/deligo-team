import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqRpc, supabaseUrl } from "@/lib/hq-server";

const allowedRoles = new Set(["SUPER_ADMIN","HUMAN_RESOURCES"]);

export async function GET() {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) return NextResponse.json({ error: "Acesso reservado a RH e Super Admin." }, { status: 403 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const headers = serviceKey ? { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Accept-Profile": "hq" } : null;
  const [employees, historyResponse, accessResponse, permissionResponse] = await Promise.all([
    hqRpc("hq_employee_directory_v1"),
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_change_history?select=*&order=created_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_access_log?select=*&order=occurred_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_permission_overrides?select=*&order=created_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
  ]);
  return NextResponse.json({ actor, employees, history: historyResponse?.ok ? await historyResponse.json() : [], access: accessResponse?.ok ? await accessResponse.json() : [], permissions: permissionResponse?.ok ? await permissionResponse.json() : [] }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) return NextResponse.json({ error: "Sem permissão para cadastrar trabalhadores." }, { status: 403 });
  const input = await request.json() as { name?: string; phone?: string; jobTitle?: string; department?: string; role?: string; activate?: boolean };
  const digits = (input.phone || "").replace(/\D/g, "");
  const phone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!input.name || !input.jobTitle || !input.department || !input.role || !/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "Preencha correctamente todos os campos." }, { status: 400 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const password = process.env.HQ_TEST_DEFAULT_PASSWORD;
  if (!serviceKey || !password) return NextResponse.json({ error: "Configuração de contas indisponível." }, { status: 503 });
  const authResponse = await fetch(`${supabaseUrl()}/auth/v1/admin/users`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ phone, password, phone_confirm: true, user_metadata: { display_name: input.name, hq_role: input.role, test_account: true, must_change_password: true } }) });
  if (!authResponse.ok) return NextResponse.json({ error: "O número já existe ou não pôde ser criado." }, { status: 409 });
  const authUser = await authResponse.json() as { id: string };
  try {
    const employee = await hqRpc("hq_create_employee_v1", { p_actor_auth_user_id: actor.authUserId, p_auth_user_id: authUser.id, p_display_name: input.name, p_phone_e164: phone, p_job_title: input.jobTitle, p_department_code: input.department, p_requested_role_code: input.role, p_activate: actor.role === "SUPER_ADMIN" && Boolean(input.activate) });
    return NextResponse.json({ employee }, { status: 201 });
  } catch (error) {
    await fetch(`${supabaseUrl()}/auth/v1/admin/users/${authUser.id}`, { method: "DELETE", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } });
    return NextResponse.json({ error: error instanceof Error && error.message.includes("SENSITIVE_ROLE") ? "Este role precisa ser criado pelo Super Admin." : "Não foi possível concluir o cadastro." }, { status: 400 });
  }
}

export async function PATCH(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || actor.role !== "SUPER_ADMIN") return NextResponse.json({ error: "Aprovação do Super Admin necessária." }, { status: 403 });
  const { employeeId, action } = await request.json() as { employeeId?: string; action?: "activate"|"suspend"|"reactivate"|"archive" };
  if (!employeeId || !action) return NextResponse.json({ error: "Operação inválida." }, { status: 400 });
  try {
    const result = await hqRpc("hq_set_employee_status_v1", { p_actor_auth_user_id: actor.authUserId, p_employee_id: employeeId, p_action: action });
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
    if (result.auth_user_id) await fetch(`${supabaseUrl()}/auth/v1/admin/users/${result.auth_user_id}`, { method: "PUT", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ ban_duration: action === "suspend" || action === "archive" ? "876000h" : "none", user_metadata: { hq_role: result.role } }) });
    return NextResponse.json({ employee: result });
  } catch { return NextResponse.json({ error: "A conta protegida não pode ser alterada ou a operação falhou." }, { status: 400 }); }
}

export async function PUT(request: NextRequest) {
  const actor = await corporateActor();
  if (!actor || !allowedRoles.has(actor.role)) return NextResponse.json({ error: "Sem permissão para editar trabalhadores." }, { status: 403 });
  const input = await request.json() as { employeeId?: string; name?: string; phone?: string; jobTitle?: string; department?: string; role?: string; updatedAt?: string };
  const digits = (input.phone || "").replace(/\D/g, "");
  const phone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!input.employeeId || !input.name?.trim() || !input.jobTitle?.trim() || !input.department || !input.role || !input.updatedAt || !/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "Dados de edição inválidos." }, { status: 400 });
  try {
    const employee = await hqRpc("hq_update_employee_v1", { p_actor_auth_user_id: actor.authUserId, p_employee_id: input.employeeId, p_display_name: input.name, p_phone_e164: phone, p_job_title: input.jobTitle, p_department_code: input.department, p_requested_role_code: input.role, p_expected_updated_at: input.updatedAt });
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (serviceKey && employee.auth_user_id) {
      const authResponse = await fetch(`${supabaseUrl()}/auth/v1/admin/users/${employee.auth_user_id}`, { method: "PUT", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ phone, phone_confirm: true, user_metadata: { display_name: input.name, hq_role: input.role } }) });
      if (!authResponse.ok) return NextResponse.json({ error: "Cadastro atualizado, mas a identidade de login precisa de reconciliação." }, { status: 409 });
    }
    return NextResponse.json({ employee });
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (message.includes("CONFLICT")) return NextResponse.json({ error: "O trabalhador foi alterado por outra pessoa. Atualize a lista e tente novamente." }, { status: 409 });
    if (message.includes("SENSITIVE_ROLE")) return NextResponse.json({ error: "Este role exige o Super Admin." }, { status: 403 });
    return NextResponse.json({ error: "Não foi possível atualizar o trabalhador." }, { status: 400 });
  }
}
