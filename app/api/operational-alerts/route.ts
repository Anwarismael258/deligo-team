import { NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const allowed = new Set(["SUPER_ADMIN", "FINANCE", "EXECUTIVE", "OPERATIONS", "TECHNOLOGY", "CUSTOMER_SUPPORT", "COMPLIANCE", "SUPERVISOR"]);
const headers = (key: string) => ({ apikey: key, Authorization: `Bearer ${key}`, "Accept-Profile": "hq", "Content-Type": "application/json" });

async function rest(key: string, path: string) {
  const response = await fetch(`${supabaseUrl()}/rest/v1/${path}`, { headers: headers(key), cache: "no-store" });
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

export async function GET() {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!actor || !key || !allowed.has(actor.role)) {
    return NextResponse.json({ data: { technicalIncidents: [] } }, { headers: { "Cache-Control": "private, no-store" } });
  }
  try {
    const [incidents, platforms] = await Promise.all([
      rest(key, "technology_incidents?select=id,platform_id,title,severity,status,description,started_at,owner_employee_id,workflow_case_id&status=not.in.(resolved,closed)&order=started_at.desc&limit=100"),
      rest(key, "platforms?select=id,name,slug&limit=20"),
    ]);
    const names = new Map(platforms.map((p: { id: string; name: string }) => [p.id, p.name]));
    return NextResponse.json({ data: { technicalIncidents: incidents.map((item: Record<string, unknown>) => ({ ...item, platform_name: item.platform_id ? names.get(String(item.platform_id)) || "Plataforma não identificada" : "HQ / Corporativo" })) } }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ data: { technicalIncidents: [] }, degraded: true }, { headers: { "Cache-Control": "private, no-store" } });
  }
}
