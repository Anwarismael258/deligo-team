import { NextRequest, NextResponse } from "next/server";
import { requireCorporatePermission, hqRpc, supabaseUrl } from "@/lib/hq-server";
import { randomBytes } from "node:crypto";

export async function GET() {
  const authorization = await requireCorporatePermission("users.view"),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para consultar colaboradores." }, { status: 403 });
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
  const authorization = await requireCorporatePermission("users.create"),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para cadastrar trabalhadores." }, { status: 403 });
  const input = await request.json() as { name?: string; phone?: string; jobTitle?: string; department?: string; role?: string; activate?: boolean };
  const digits = (input.phone || "").replace(/\D/g, "");
  const phone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!input.name || !input.jobTitle || !input.department || !input.role || !/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "Preencha correctamente todos os campos." }, { status: 400 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) return NextResponse.json({ error: "Configuração de contas indisponível." }, { status: 503 });
  const bootstrapPassword = randomBytes(32).toString("base64url");
  const authResponse = await fetch(`${supabaseUrl()}/auth/v1/admin/users`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ phone, password: bootstrapPassword, phone_confirm: false, user_metadata: { display_name: input.name, hq_role: input.role, auth_method: "phone_otp", must_set_password: true } }) });
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
  const body = await request.json() as { employeeId?: string; action?: "activate"|"suspend"|"reactivate"|"archive"|"set_supervisor"|"set_permission"; supervisorId?: string|null; permissionCode?: string; allowed?: boolean };
  const { employeeId, action } = body;
  if (!employeeId || !action) return NextResponse.json({ error: "Operação inválida." }, { status: 400 });
  const permission=action==="set_supervisor"||action==="set_permission"?"settings.manage":"users.suspend",authorization=await requireCorporatePermission(permission),actor=authorization?.actor;
  if(!actor)return NextResponse.json({error:"Sem permissão para esta alteração de acesso."},{status:403});
  if (action === "set_supervisor" || action === "set_permission") {
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!serviceKey) return NextResponse.json({ error: "Configuração administrativa indisponível." }, { status: 503 });
    const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json", "Content-Profile": "hq", Prefer: "return=representation,resolution=merge-duplicates" };
    if (action === "set_supervisor") {
      if (body.supervisorId === employeeId) return NextResponse.json({ error: "Um colaborador não pode supervisionar a própria conta." }, { status: 400 });
      const response = await fetch(`${supabaseUrl()}/rest/v1/employees?id=eq.${encodeURIComponent(employeeId)}`, { method:"PATCH", headers, body:JSON.stringify({ manager_id: body.supervisorId || null, updated_at:new Date().toISOString() }) });
      if (!response.ok) return NextResponse.json({ error:"Não foi possível atribuir o supervisor." }, { status:400 });
    } else {
      const catalog=["people.view","people.manage","operations.view","reports.view","users.view","users.create","users.edit","users.suspend","finance.view","finance.createExpense","finance.approvePayment","hr.viewEmployees","hr.viewSalary","hr.approveLeave","support.viewTickets","support.reply","support.close","field.createVisit","field.submitKyc","field.approveKyc","legal.viewContracts","legal.approveContract","audit.view","platform.manage","settings.manage"];
      if (!body.permissionCode || !catalog.includes(body.permissionCode)) return NextResponse.json({ error:"Permissão inválida." }, { status:400 });
      const response = await fetch(`${supabaseUrl()}/rest/v1/employee_permission_overrides?on_conflict=employee_id,permission_code`, { method:"POST", headers, body:JSON.stringify({ employee_id:employeeId, permission_code:body.permissionCode, allowed:Boolean(body.allowed) }) });
      if (!response.ok) return NextResponse.json({ error:"Não foi possível alterar a permissão." }, { status:400 });
    }
    await fetch(`${supabaseUrl()}/rest/v1/employee_change_history`, { method:"POST", headers, body:JSON.stringify({ employee_id:employeeId, action, after_state:body }) });
    return NextResponse.json({ ok:true });
  }
  try {
    const result = await hqRpc("hq_set_employee_status_v1", { p_actor_auth_user_id: actor.authUserId, p_employee_id: employeeId, p_action: action });
    const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
    if (result.auth_user_id) await fetch(`${supabaseUrl()}/auth/v1/admin/users/${result.auth_user_id}`, { method: "PUT", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ ban_duration: action === "suspend" || action === "archive" ? "876000h" : "none", user_metadata: { hq_role: result.role } }) });
    return NextResponse.json({ employee: result });
  } catch { return NextResponse.json({ error: "A conta protegida não pode ser alterada ou a operação falhou." }, { status: 400 }); }
}

export async function PUT(request: NextRequest) {
  const authorization=await requireCorporatePermission("users.edit"),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para editar trabalhadores." }, { status: 403 });
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
