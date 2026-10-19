import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

export async function POST(request: NextRequest) {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const bucket = process.env.HQ_PROFILE_MEDIA_BUCKET || process.env.HQ_SUPPORT_ATTACHMENTS_BUCKET;
  if (!actor || !key) return NextResponse.json({ error: "Sessão inválida." }, { status: 401 });
  if (!bucket) return NextResponse.json({ error: "O armazenamento de fotografias de perfil não está configurado." }, { status: 503 });
  const file = (await request.formData()).get("file");
  if (!(file instanceof File)) return NextResponse.json({ error: "Seleccione uma fotografia." }, { status: 400 });
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) return NextResponse.json({ error: "Use JPG, PNG ou WEBP." }, { status: 400 });
  if (file.size <= 0 || file.size > 5 * 1024 * 1024) return NextResponse.json({ error: "A fotografia deve ter no máximo 5 MB." }, { status: 400 });
  const path = `profiles/${actor.employee_id}/${crypto.randomUUID()}.${file.type.split("/")[1]}`;
  const upload = await fetch(`${supabaseUrl()}/storage/v1/object/${encodeURIComponent(bucket)}/${path.split("/").map(encodeURIComponent).join("/")}`, { method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": file.type, "x-upsert": "false" }, body: await file.arrayBuffer(), cache: "no-store" });
  if (!upload.ok) return NextResponse.json({ error: "Não foi possível guardar a fotografia." }, { status: 502 });
  const avatarUrl = `${supabaseUrl()}/storage/v1/object/public/${bucket}/${path}`;
  const profileResponse = await fetch(`${supabaseUrl()}/rest/v1/employee_display_profiles?employee_id=eq.${encodeURIComponent(actor.employee_id)}`, { method: "PATCH", headers: { apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "hq", "Content-Profile": "hq", "Content-Type": "application/json", Prefer: "return=representation" }, body: JSON.stringify({ avatar_url: avatarUrl }) });
  if (!profileResponse.ok) return NextResponse.json({ error: "Fotografia guardada, mas não foi possível actualizar o perfil." }, { status: 502 });
  return NextResponse.json({ avatar_url: avatarUrl });
}
