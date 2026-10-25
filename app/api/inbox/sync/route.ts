import { NextResponse } from "next/server";
import { corporateActor } from "@/lib/hq-server";
import { syncNominaliaMailboxes } from "@/lib/nominalia-imap";

export async function POST() {
  const actor = await corporateActor();
  if (!actor || !["SUPER_ADMIN", "FINANCE", "CUSTOMER_SUPPORT", "SUPERVISOR"].includes(actor.role)) return NextResponse.json({ error: "Sem permissão para sincronizar a caixa." }, { status: 403 });
  try {
    const results = await syncNominaliaMailboxes();
    return NextResponse.json({ ok: true, results }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("NOMINALIA_IMAP_SYNC_FAILED", error instanceof Error ? error.message : "unknown");
    return NextResponse.json({ error: "Não foi possível sincronizar a caixa Nominalia. Confirme as variáveis IMAP no servidor." }, { status: 502 });
  }
}
