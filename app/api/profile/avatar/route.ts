import { NextRequest, NextResponse } from "next/server";
import { corporateActor, hqServiceKey, supabaseUrl } from "@/lib/hq-server";

export async function POST(request: NextRequest) {
  try {
    const actor = await corporateActor();
    const key = hqServiceKey();
    const bucket = process.env.HQ_PROFILE_MEDIA_BUCKET || "hq-profile-media";
    if (!actor || !key) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });
    if (!bucket) return NextResponse.json({ error: "O armazenamento de fotografias de perfil não está configurado." }, { status: 503 });
    const file = (await request.formData()).get("file");
    if (!(file instanceof File)) return NextResponse.json({ error: "Seleccione uma fotografia." }, { status: 400 });
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) return NextResponse.json({ error: "Use JPG, PNG ou WEBP." }, { status: 400 });
    if (file.size <= 0 || file.size > 5 * 1024 * 1024) return NextResponse.json({ error: "A fotografia deve ter no máximo 5 MB." }, { status: 400 });
    const path = `profiles/${actor.employee_id}/${crypto.randomUUID()}.${file.type.split("/")[1]}`;
    const privileged: Record<string, string> = key.startsWith("sb_secret_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };
    const upload = await fetch(`${supabaseUrl()}/storage/v1/object/${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`, { method: "POST", headers: { ...privileged, "Content-Type": file.type, "x-upsert": "false" }, body: await file.arrayBuffer(), cache: "no-store" });
    if (!upload.ok) return NextResponse.json({ error: "Não foi possível guardar a fotografia." }, { status: 502 });
    const avatarUrl = `${supabaseUrl()}/storage/v1/object/public/${bucket}/${path}`;
    const existingResponse = await fetch(`${supabaseUrl()}/rest/v1/employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}&select=employee_id,biography,personal_phone,alternate_contact,account_preferences`, { headers: { ...privileged, "Accept-Profile": "hq" }, cache: "no-store" });
    const existing = existingResponse.ok ? ((await existingResponse.json()) as Array<Record<string, unknown>>)[0] : undefined;
    const profilePayload = { avatar_url: avatarUrl, biography: existing?.biography ?? null, personal_phone: existing?.personal_phone ?? null, alternate_contact: existing?.alternate_contact ?? null, account_preferences: existing?.account_preferences ?? {} };
    const profileResponse = await fetch(`${supabaseUrl()}/rest/v1/employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}`, { method: existing?.employee_id ? "PATCH" : "POST", headers: { ...privileged, "Accept-Profile": "hq", "Content-Profile": "hq", "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify(existing?.employee_id ? profilePayload : { employee_id: actor.employee_id, ...profilePayload }) });
    if (!profileResponse.ok) return NextResponse.json({ error: "Fotografia guardada, mas não foi possível actualizar o perfil." }, { status: 502 });
    return NextResponse.json({ avatar_url: avatarUrl });
  } catch (error) {
    console.error("profile avatar upload failed", error);
    return NextResponse.json({ error: "Não foi possível guardar a fotografia." }, { status: 502 });
  }
}
