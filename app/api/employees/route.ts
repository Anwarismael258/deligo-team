import { NextRequest, NextResponse } from "next/server";
import { corporateActor, requireCorporatePermission, hqRpc, hqRest, hqServiceKey, supabaseUrl } from "@/lib/hq-server";
import { randomBytes } from "node:crypto";

const EMPLOYEE_CARGOS: Record<string, { role: string; department: string; title: string }> = {
  CEO: { role: "SUPER_ADMIN", department: "EXECUTIVE", title: "CEO e Fundador" },
  FINANCE: { role: "FINANCE_DIRECTOR", department: "FINANCE", title: "Diretora Financeira" },
  SUPERVISOR: { role: "OPERATIONS_SUPERVISOR", department: "OPERATIONS", title: "Supervisor" },
  FIELD: { role: "FIELD", department: "FIELD", title: "Agente de Operações de Campo" },
  CUSTOMER_SUPPORT: { role: "CUSTOMER_SUPPORT", department: "SUPPORT", title: "Agente de Apoio ao Cliente" },
  MARKETING: { role: "MARKETING", department: "MARKETING", title: "Agente de Marketing" },
};

function resolveCargo(input: { cargo?: string; role?: string; jobTitle?: string }) {
  const key = String(input.cargo || input.role || "").trim().toUpperCase();
  if (EMPLOYEE_CARGOS[key]) return EMPLOYEE_CARGOS[key];
  const title = String(input.jobTitle || "").trim().toLowerCase();
  const match = Object.values(EMPLOYEE_CARGOS).find(item => item.title.toLowerCase() === title);
  return match || null;
}

async function readAuthError(response: Response) {
  const raw = await response.text().catch(() => "");
  try {
    const parsed = JSON.parse(raw) as { code?: string; error_code?: string; msg?: string; message?: string; error_description?: string };
    return {
      code: String(parsed.code || parsed.error_code || "").toLowerCase(),
      message: String(parsed.msg || parsed.message || parsed.error_description || "").toLowerCase(),
    };
  } catch {
    return { code: "", message: raw.toLowerCase() };
  }
}

function rpcErrorCode(error: unknown) {
  const message = error instanceof Error ? error.message : String(error || "");
  const match = message.match(/(?:code|message|error)"?\s*[:=]\s*"?([A-Z][A-Z0-9_]+)/i);
  return (match?.[1] || message).toUpperCase();
}

async function findAuthUserByPhone(serviceKey: string, phone: string) {
  const response = await fetch(`${supabaseUrl()}/auth/v1/admin/users?page=1&per_page=1000`, {
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
    cache: "no-store",
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) return null;
  const body = await response.json().catch(() => ({})) as { users?: Array<{ id: string; phone?: string | null }> };
  const wanted = phone.replace(/\D/g, "");
  return body.users?.find(user => {
    const candidate = String(user.phone || "").replace(/\D/g, "");
    return candidate === wanted || (candidate.endsWith(wanted.slice(-9)) && wanted.endsWith(candidate.slice(-9)));
  }) || null;
}

export async function GET() {
  const authorization = await requireCorporatePermission("users.view"),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para consultar colaboradores." }, { status: 403 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const headers = serviceKey ? { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Accept-Profile": "hq" } : null;
  const [employees, historyResponse, accessResponse, permissionResponse, profilesResponse] = await Promise.all([
    hqRpc("hq_employee_directory_v1"),
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_change_history?select=*&order=created_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_access_log?select=*&order=occurred_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_permission_overrides?select=*&order=created_at.desc&limit=250`, { headers, cache: "no-store" }) : null,
    headers ? fetch(`${supabaseUrl()}/rest/v1/employee_display_profiles?select=employee_id,avatar_url,biography&limit=500`, { headers, cache: "no-store" }) : null,
  ]);
  const profiles=profilesResponse?.ok?await profilesResponse.json() as Array<{employee_id:string;avatar_url?:string|null;biography?:string|null}>:[];
  const profileByEmployee=new Map(profiles.map(profile=>[profile.employee_id,profile]));
  return NextResponse.json({ actor, employees:(employees||[]).map((employee:Record<string,unknown>)=>({...employee,name:employee.name||employee.display_name||"Trabalhador",job_title:employee.job_title||employee.title||null,department_name:employee.department_name||employee.department||null,avatar_url:profileByEmployee.get(String(employee.id))?.avatar_url||null,biography:profileByEmployee.get(String(employee.id))?.biography||null})), history: historyResponse?.ok ? await historyResponse.json() : [], access: accessResponse?.ok ? await accessResponse.json() : [], permissions: permissionResponse?.ok ? await permissionResponse.json() : [] }, { headers: { "Cache-Control": "private, no-store" } });
}

export async function POST(request: NextRequest) {
  const authorization = await requireCorporatePermission("users.create");
  // Keep the role guard as a safe compatibility path for production projects
  // whose permission catalogue is one migration behind. The RPC below still
  // performs the authoritative active-employee check before inserting.
  const fallbackActor = authorization?.actor || await corporateActor();
  if (!fallbackActor) return NextResponse.json({ error: "Sem permissão para cadastrar trabalhadores." }, { status: 403 });
  if (!new Set(["SUPER_ADMIN", "SUPERVISOR", "OPERATIONS_SUPERVISOR", "FINANCE", "FINANCE_DIRECTOR"]).has(fallbackActor.role)) return NextResponse.json({ error: "Apenas CEO, Finanças ou Supervisor podem cadastrar trabalhadores." }, { status: 403 });
  const input = await request.json() as { name?: string; phone?: string; cargo?: string; jobTitle?: string; department?: string; role?: string; activate?: boolean };
  const cargo = resolveCargo(input);
  const digits = (input.phone || "").replace(/\D/g, "");
  const phone = digits.startsWith("258") ? `+${digits}` : `+258${digits.replace(/^0/, "")}`;
  if (!input.name?.trim() || !cargo || !/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "Indique o nome, o telefone moçambicano e um cargo válido." }, { status: 400 });
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceKey) return NextResponse.json({ error: "Configuração de contas indisponível." }, { status: 503 });
  const existing = await hqRest(`employees?phone_e164=eq.${encodeURIComponent(phone)}&select=id,display_name,status,requested_role_code&limit=1`) as Array<Record<string, unknown>>;
  if (existing?.[0]) return NextResponse.json({ error: `Este número já está registado para ${String(existing[0].display_name || "um trabalhador")}. Função actual: ${String(existing[0].requested_role_code || "pendente")} · estado: ${String(existing[0].status || "não indicado")}.` }, { status: 409 });
  let authUser: { id: string } | null = null;
  let reusedAuthUser = false;
  const bootstrapPassword = randomBytes(32).toString("base64url");
  try {
    const authResponse = await fetch(`${supabaseUrl()}/auth/v1/admin/users`, { method: "POST", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ phone, password: bootstrapPassword, phone_confirm: false, user_metadata: { display_name: input.name, hq_role: cargo.role, auth_method: "phone_otp", must_set_password: true } }), signal: AbortSignal.timeout(8_000) });
    if (authResponse.ok) authUser = await authResponse.json() as { id: string };
    else {
      const authError = await readAuthError(authResponse);
      const isDuplicate = /already|exists|duplicate|registered|phone_exists|user_already_exists/.test(`${authError.code} ${authError.message}`);
      if (!isDuplicate) {
        console.error("EMPLOYEE_AUTH_CREATE_REJECTED", { code: authError.code || "unknown" });
        return NextResponse.json({ error: "A autenticação recusou o cadastro deste número. Verifique o formato e tente novamente." }, { status: 409 });
      }
      authUser = await findAuthUserByPhone(serviceKey, phone);
      reusedAuthUser = Boolean(authUser);
    }
  } catch (error) {
    console.error("EMPLOYEE_AUTH_CREATE_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "O serviço de autenticação não respondeu. Tente novamente em alguns segundos." }, { status: 504 });
  }
  if (!authUser?.id) return NextResponse.json({ error: "A conta deste número existe, mas não foi possível localizá-la para associação segura." }, { status: 409 });
  try {
    const employee = await Promise.race([
      hqRpc("hq_create_employee_v1", { p_actor_auth_user_id: fallbackActor.authUserId, p_auth_user_id: authUser.id, p_display_name: input.name.trim(), p_phone_e164: phone, p_job_title: cargo.title, p_department_code: cargo.department, p_requested_role_code: cargo.role, p_activate: fallbackActor.role === "SUPER_ADMIN" }),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("HQ_EMPLOYEE_CREATE_TIMEOUT")), 15_000)),
    ]);
    return NextResponse.json({ employee }, { status: 201 });
  } catch (error) {
    if (!reusedAuthUser) await fetch(`${supabaseUrl()}/auth/v1/admin/users/${authUser.id}`, { method: "DELETE", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` }, signal: AbortSignal.timeout(5_000) }).catch(() => undefined);
    const message = error instanceof Error ? error.message : "";
    if (message.includes("SENSITIVE_ROLE")) return NextResponse.json({ error: "Este cargo só pode ser criado pelo CEO." }, { status: 403 });
    if (message.includes("INVALID_DEPARTMENT_OR_ROLE")) return NextResponse.json({ error: "O cargo não está disponível no catálogo do backend." }, { status: 409 });
    if (message.includes("EMPLOYEE_ADMIN_FORBIDDEN")) return NextResponse.json({ error: "Este perfil não pode cadastrar trabalhadores." }, { status: 403 });
    if (message.includes("EMPLOYEE_CREATE_TIMEOUT")) return NextResponse.json({ error: "O backend demorou a responder. O cadastro não foi confirmado; actualize a equipa antes de tentar novamente." }, { status: 504 });
    if (message.includes("HQ_EMPLOYEE_AUTH_ALREADY_LINKED")) return NextResponse.json({ error: "Esta identidade já está associada a outro trabalhador da Central. Actualize a lista antes de tentar novamente." }, { status: 409 });
    return NextResponse.json({ error: "Não foi possível concluir o cadastro." }, { status: 400 });
  }
}

export async function PATCH(request: NextRequest) {
  const body = await request.json() as { employeeId?: string; action?: "activate"|"suspend"|"reactivate"|"archive"|"set_supervisor"|"set_permission"; supervisorId?: string|null; permissionCode?: string; allowed?: boolean };
  const { employeeId, action } = body;
  if (!employeeId || !action) return NextResponse.json({ error: "Operação inválida." }, { status: 400 });
  const permission=action==="set_supervisor"||action==="set_permission"?"settings.manage":"users.suspend",authorization=await requireCorporatePermission(permission),actor=authorization?.actor;
  if(!actor)return NextResponse.json({error:"Sem permissão para esta alteração de acesso."},{status:403});
  if (["suspend", "archive"].includes(action) && actor.role !== "SUPER_ADMIN") return NextResponse.json({ error: "Só o CEO pode suspender ou eliminar contas." }, { status: 403 });
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
  } catch (error) {
    const code=rpcErrorCode(error);
    if(code.includes("FOUNDER_ACCOUNT_PROTECTED")) return NextResponse.json({error:"A conta do CEO fundador está protegida."},{status:403});
    if(code.includes("NOT_FOUND")) return NextResponse.json({error:"O trabalhador já não existe. Actualize a lista da equipa."},{status:404});
    if(code.includes("SUPER_ADMIN_APPROVAL_REQUIRED")) return NextResponse.json({error:"Só o CEO pode suspender ou arquivar contas."},{status:403});
    // Production can still expose an older RPC that resolves the actor by a
    // legacy Auth identity. The request is already authenticated and the
    // CEO-only guard ran above, so keep lifecycle actions usable through a
    // narrowly scoped service-role compatibility path.
    if (["suspend", "archive"].includes(action) && actor.role === "SUPER_ADMIN") {
      try {
        const target = (await hqRest(`employees?id=eq.${encodeURIComponent(employeeId)}&select=id,auth_user_id,status`))?.[0] as Record<string, unknown> | undefined;
        if (!target?.id) return NextResponse.json({ error: "O trabalhador já não existe. Actualize a lista da equipa." }, { status: 404 });
        const nextStatus = action === "archive" ? "offboarded" : "suspended";
        const updated = await hqRest(`employees?id=eq.${encodeURIComponent(employeeId)}`, { method: "PATCH", body: JSON.stringify({ status: nextStatus, ...(nextStatus === "suspended" ? { suspended_at: new Date().toISOString() } : { offboarded_at: new Date().toISOString() }), updated_at: new Date().toISOString() }) });
        if (action === "archive") {
          await hqRest(`employee_roles?employee_id=eq.${encodeURIComponent(employeeId)}&revoked_at=is.null`, { method: "PATCH", body: JSON.stringify({ revoked_at: new Date().toISOString() }) }).catch(() => undefined);
          await hqRest(`employee_platforms?employee_id=eq.${encodeURIComponent(employeeId)}&revoked_at=is.null`, { method: "PATCH", body: JSON.stringify({ revoked_at: new Date().toISOString() }) }).catch(() => undefined);
        }
        const serviceKey = hqServiceKey();
        if (serviceKey && target.auth_user_id) await fetch(`${supabaseUrl()}/auth/v1/admin/users/${target.auth_user_id}`, { method: "PUT", headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" }, body: JSON.stringify({ ban_duration: "876000h" }) }).catch(() => undefined);
        await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: actor.employee_id, action: `EMPLOYEE_${action.toUpperCase()}_COMPATIBILITY`, module: "people", target_type: "employee", target_id: employeeId, result: "success", metadata: { previous_status: target.status, new_status: nextStatus, rpc_error: code } }) }).catch(() => undefined);
        return NextResponse.json({ employee: Array.isArray(updated) ? updated[0] : updated, compatibilityPath: true });
      } catch (fallbackError) {
        console.error("EMPLOYEE_STATUS_COMPATIBILITY_FAILED", fallbackError instanceof Error ? fallbackError.message : "unknown");
      }
    }
    console.error("EMPLOYEE_STATUS_UPDATE_FAILED",code);
    return NextResponse.json({ error: "A conta não foi alterada. A origem devolveu um erro de autorização; actualize a equipa e tente novamente." }, { status: 400 });
  }
}

export async function PUT(request: NextRequest) {
  const authorization=await requireCorporatePermission("users.edit"),actor=authorization?.actor;
  if (!actor) return NextResponse.json({ error: "Sem permissão para editar trabalhadores." }, { status: 403 });
  const input = await request.json() as { employeeId?: string; name?: string; jobTitle?: string; department?: string; role?: string; updatedAt?: string };
  if (!input.employeeId || !input.name?.trim() || !input.jobTitle?.trim() || !input.department || !input.role || !input.updatedAt) return NextResponse.json({ error: "Dados de edição inválidos." }, { status: 400 });
  try {
    const directory = await hqRpc("hq_employee_directory_v1") as Array<Record<string, unknown>>;
    const current = directory.find(employee => String(employee.id) === String(input.employeeId));
    const phone = String(current?.phone || current?.phone_e164 || "");
    if (!/^\+258\d{9}$/.test(phone)) return NextResponse.json({ error: "O número registado não é válido; não é possível editar este trabalhador." }, { status: 409 });
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
