import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, hqRest } from "@/lib/hq-server";
import { getReportData, type ReportType } from "@/lib/report-data";

const allowed = new Set(["SUPER_ADMIN", "SUPERVISOR", "FINANCE", "MARKETING", "FIELD", "CUSTOMER_SUPPORT"]);
const csvCell = (value: unknown) => { const raw = String(value ?? ""); const safe = /^[=+\-@]/.test(raw) ? `'${raw}` : raw; return `"${safe.replaceAll('"', '""')}"`; };
import {reportColumns,reportTitles,reportFilterLines,reportSummaryLines,reportRowValues} from "@/lib/report-presentation";
import {reportPdf} from "@/lib/report-export";

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization();
  if (!authorization || (!authorization.isSuperAdmin && !allowed.has(authorization.actor.role))) return NextResponse.json({ error: "Sem acesso à exportação." }, { status: 403 });
  const query = request.nextUrl.searchParams;
  const type = (["financial", "marketing", "field", "support"].includes(query.get("type") || "") ? query.get("type") : "financial") as ReportType;
  const format = query.get("format") === "pdf" ? "pdf" : "csv";
  const data = await getReportData(type, { period: query.get("period"), from: query.get("from"), to: query.get("to"), platform: query.get("platform"), department: query.get("department"), responsible: query.get("responsible"), status: query.get("status"), allowedPlatforms: authorization.isSuperAdmin ? null : [...authorization.platformIds, ...authorization.platformSlugs] });
  if(data.sourceState==="unavailable")return NextResponse.json({error:"A fonte do relatório está indisponível. O ficheiro não foi gerado.",source:data.source},{status:503});
  const rows = data.records; const columns=reportColumns; const values=rows.map(row=>reportRowValues(row as unknown as Record<string,unknown>));
  const filters = Object.fromEntries(["period", "from", "to", "platform", "department", "responsible", "status"].map(key => [key, query.get(key) || "Todas"]));
  await hqRest("report_runs", { method: "POST", body: JSON.stringify({ report_type: type, filters, format, row_count: rows.length, generated_by: authorization.actor.employee_id }) }).catch(error => console.error("REPORT_EXPORT_HISTORY_FAILED",error));
  await hqRest("audit_logs", { method: "POST", body: JSON.stringify({ actor_employee_id: authorization.actor.employee_id, action: "report_export", module: "reports", target_type: type, result: "success", metadata: { format, row_count: rows.length, filters, source: data.source } }) }).catch(error => console.error("REPORT_EXPORT_HISTORY_FAILED",error));
  if(format==="pdf"){
    const labels=reportColumns;
    const sourceLabel=reportTitles[type]||"Central";
    const lines=[`DeliGo Triunfal - Relatório de ${sourceLabel}`,...reportFilterLines(filters,data.range),`Gerado em: ${new Date().toLocaleString("pt-MZ",{timeZone:"Africa/Maputo"})}`,`Fonte: registos autorizados de ${sourceLabel}`,`Estado da leitura: ${data.sourceState==="empty"?"Sem registos":"Actualizada"}`,"Resumo do período",...reportSummaryLines(data.summary),"",...data.limitations.map(x=>`Indicador indisponível: ${x}`),"",...values.flatMap((row,i)=>[`Registo ${i+1}`, ...row.map((value,j)=>`${labels[j]}: ${String(value??"Não indicado")}`),""])];
    return new NextResponse(reportPdf(lines),{headers:{"Content-Type":"application/pdf","Content-Disposition":`attachment; filename="deligo-relatorio-${type}.pdf"`,"Cache-Control":"private, no-store"}});
  }
  const csv = [columns, ...values].map(row => row.map(csvCell).join(",")).join("\r\n"); return new NextResponse(`\uFEFF${csv}`, { headers: { "Cache-Control":"private, no-store", "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="deligo-relatorio-${type}.csv"` } });
}
