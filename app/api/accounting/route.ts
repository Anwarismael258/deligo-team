import { NextRequest, NextResponse } from "next/server";
import { corporateActor, supabaseUrl } from "@/lib/hq-server";

const allowed = new Set(["SUPER_ADMIN", "FINANCE", "ACCOUNTING"]);
const entity = "10000000-0000-0000-0000-000000000001";
const names = ["chart_of_accounts", "accounting_periods", "journal_entries", "journal_lines", "account_reconciliations", "accounting_invoices", "tax_obligations"];
const headers = (key: string) => ({ apikey:key, Authorization:`Bearer ${key}`, "Accept-Profile":"hq", "Content-Profile":"hq", "Content-Type":"application/json", Prefer:"return=representation" });

async function context() {
  const actor = await corporateActor();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  return actor && key && allowed.has(actor.role) ? { actor, key } : null;
}

export async function GET() {
  const c = await context();
  if (!c) return NextResponse.json({ error:"Acesso contabilístico restrito." }, { status:403 });
  const rows = await Promise.all(names.map(async (name) => {
    const response = await fetch(`${supabaseUrl()}/rest/v1/${name}?select=*&limit=1000`, { headers:headers(c.key), cache:"no-store" });
    return [name, response.ok ? await response.json() : []] as const;
  }));
  const data = Object.fromEntries(rows) as Record<string, Array<Record<string, unknown>>>;
  const posted = new Set(data.journal_entries.filter((entry) => entry.status === "posted").map((entry) => entry.id));
  const accounts = new Map(data.chart_of_accounts.map((account) => [account.id, account]));
  const balances: Record<string, { code:string; name:string; class:string; debit:number; credit:number; balance:number }> = {};
  for (const line of data.journal_lines.filter((item) => posted.has(item.journal_entry_id))) {
    const account = accounts.get(line.account_id);
    if (!account) continue;
    const code = String(account.code);
    const current = balances[code] || { code, name:String(account.name), class:String(account.account_class), debit:0, credit:0, balance:0 };
    current.debit += Number(line.debit || 0);
    current.credit += Number(line.credit || 0);
    current.balance = current.debit - current.credit;
    balances[code] = current;
  }
  const values = Object.values(balances);
  const revenue = values.filter((v) => v.class === "revenue").reduce((sum, v) => sum + v.credit - v.debit, 0);
  const expense = values.filter((v) => v.class === "expense").reduce((sum, v) => sum + v.debit - v.credit, 0);
  const assets = values.filter((v) => v.class === "asset").reduce((sum, v) => sum + v.debit - v.credit, 0);
  const liabilities = values.filter((v) => v.class === "liability").reduce((sum, v) => sum + v.credit - v.debit, 0);
  const equity = values.filter((v) => v.class === "equity").reduce((sum, v) => sum + v.credit - v.debit, 0);
  return NextResponse.json({ data, reports:{ trialBalance:values, revenue, expense, netIncome:revenue-expense, assets, liabilities, equity, cashflow:values.find((v) => v.code === "11")?.balance || 0 } }, { headers:{ "Cache-Control":"private, no-store" } });
}

export async function POST(request: NextRequest) {
  const c = await context();
  if (!c) return NextResponse.json({ error:"Sem permissão contabilística." }, { status:403 });
  const body = await request.json() as { entryDate?:string; description?:string; platformId?:string; lines?:Array<{ account_id:string; debit:number; credit:number }> };
  const lines = body.lines || [];
  const debit = lines.reduce((sum, line) => sum + Number(line.debit || 0), 0);
  const credit = lines.reduce((sum, line) => sum + Number(line.credit || 0), 0);
  if (!body.entryDate || !body.description || lines.length < 2 || debit <= 0 || Math.abs(debit-credit) > 0.001) return NextResponse.json({ error:"O lançamento deve ter pelo menos duas linhas e débitos iguais aos créditos." }, { status:400 });
  const h = headers(c.key);
  const response = await fetch(`${supabaseUrl()}/rest/v1/journal_entries`, { method:"POST", headers:h, body:JSON.stringify({ legal_entity_id:entity, platform_id:body.platformId || null, entry_date:body.entryDate, description:body.description, status:"draft", created_by:c.actor.employee_id }) });
  if (!response.ok) return NextResponse.json({ error:"Não foi possível criar o lançamento." }, { status:400 });
  const entry = (await response.json())[0];
  const lineResponse = await fetch(`${supabaseUrl()}/rest/v1/journal_lines`, { method:"POST", headers:h, body:JSON.stringify(lines.map((line) => ({ ...line, journal_entry_id:entry.id }))) });
  if (!lineResponse.ok) return NextResponse.json({ error:"Lançamento criado, mas as linhas precisam de revisão." }, { status:409 });
  return NextResponse.json({ entry }, { status:201 });
}
