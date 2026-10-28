import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";
import { getReportData, type ReportType } from "@/lib/report-data";

const allowed = new Set(["SUPER_ADMIN", "SUPERVISOR", "FINANCE", "MARKETING", "FIELD", "CUSTOMER_SUPPORT"]);
const csvCell = (value: unknown) => { const raw = String(value ?? ""); const safe = /^[=+\-@]/.test(raw) ? `'${raw}` : raw; return `"${safe.replaceAll('"', '""')}"`; };
const pdfText = (value: string) => value.replaceAll("\\", "\\\\").replaceAll("(", "\\(").replaceAll(")", "\\)").replaceAll(/[^ -~]/g, "?");
function makePdf(lines: string[]) {
  const pages = Array.from({ length: Math.max(1, Math.ceil(lines.length / 48)) }, (_, index) => lines.slice(index * 48, index * 48 + 48));
  const objects: string[] = ["<< /Type /Catalog /Pages 2 0 R >>", ""];
  for (const page of pages) { const content = `BT /F1 9 Tf 36 805 Td ${page.map((line, index) => `${index ? "0 -14 Td " : ""}(${pdfText(line.slice(0, 120))}) Tj`).join(" ")} ET`; objects.push("", `<< /Length ${content.length} >>\nstream\n${content}\nendstream`); }
  const fontObject = objects.length + 1; objects.push("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
  const pageRefs = pages.map((_, index) => `${3 + index * 2} 0 R`).join(" "); objects[1] = `<< /Type /Pages /Kids [${pageRefs}] /Count ${pages.length} >>`;
  pages.forEach((_, index) => { objects[2 + index * 2] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 ${fontObject} 0 R >> >> /Contents ${4 + index * 2} 0 R >>`; });
  let output = "%PDF-1.4\n"; const offsets = [0]; objects.forEach((object, index) => { offsets.push(output.length); output += `${index + 1} 0 obj\n${object}\nendobj\n`; }); const xref = output.length;
  output += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, "0")} 00000 n `).join("\n")}\ntrailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return output;
}

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization || (!authorization.isSuperAdmin && !allowed.has(authorization.actor.role))) return NextResponse.json({ error: "Sem acesso à exportação." }, { status: 403 });
  const query = request.nextUrl.searchParams;
  const type = (["financial", "marketing", "field", "support"].includes(query.get("type") || "") ? query.get("type") : "financial") as ReportType;
  const format = query.get("format") === "pdf" ? "pdf" : "csv";
  const data = await getReportData(type, { period: query.get("period"), from: query.get("from"), to: query.get("to"), platform: query.get("platform"), department: query.get("department"), responsible: query.get("responsible"), status: query.get("status"), allowedPlatforms: authorization.isSuperAdmin ? null : [...authorization.platformIds, ...authorization.platformSlugs] });
  const rows = data.records; const columns = ["id", "date", "reference", "platform", "category", "value", "currency", "status", "responsible", "client", "subject"] as const; const values = rows.map(row => columns.map(column => row[column]));
  const filters = Object.fromEntries(["period", "from", "to", "platform", "department", "responsible", "status"].map(key => [key, query.get(key) || "Todas"]));
  await hqRest("report_runs", { method: "POST", body: JSON.stringify({ report_type: type, period_start: data.range.from, period_end: data.range.to, filters, format, row_count: rows.length, status: "generated", snapshot: { source: data.source, source_state: data.sourceState, summary: data.summary, rows }, generated_by: authorization.actor.employee_id }) }).catch(() => undefined);
  await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: authorization.actor.employee_id, action: "report_export", module: "reports", target_type: type, result: "success", metadata: { format, row_count: rows.length, filters, source: data.source } }) }).catch(() => undefined);
  if (format === "pdf") { const lines = [`DeliGo Triunfal · Relatório ${type}`, `Período: ${data.range.from} a ${data.range.to}`, `Fonte: ${data.source} · Estado: ${data.sourceState}`, `Registos: ${rows.length}`, `Filtros: ${JSON.stringify(filters)}`, "", ...(data.limitations.length ? [`Indisponível: ${data.limitations.join("; ")}`, ""] : []), columns.join(" | "), ...values.map(row => row.map(value => String(value ?? "—")).join(" | "))]; return new NextResponse(makePdf(lines), { headers: { "Content-Type": "application/pdf", "Content-Disposition": `attachment; filename="deligo-relatorio-${type}.pdf"` } }); }
  const csv = [columns, ...values].map(row => row.map(csvCell).join(",")).join("\r\n"); return new NextResponse(`\uFEFF${csv}`, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="deligo-relatorio-${type}.csv"` } });
}
