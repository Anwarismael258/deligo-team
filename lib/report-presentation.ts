export const reportTitles:Record<string,string>={financial:"Finanças",marketing:"Marketing",field:"Operações de Campo",support:"Apoio ao Cliente"};
export const reportColumns=["ID","Data","Referência","Plataforma","Categoria","Valor","Moeda","Estado","Responsável","Cliente","Assunto"];
const labels:Record<string,string>={pending:"Pendente",open:"Aberto",closed:"Encerrado",in_progress:"Em curso",submitted:"Submetido",approved:"Aprovado",rejected:"Rejeitado",paid:"Pago",completed:"Concluído",confirmed:"Confirmado",cancelled:"Cancelado",failed:"Falhou",processing:"Em processamento",revenue:"Receita",commission:"Comissão",fee:"Taxa",expense:"Despesa",deposit:"Depósito",withdrawal:"Levantamento",credit:"Crédito",debit:"Débito",income:"Receita",support:"Apoio ao Cliente",financial:"Finanças",marketing:"Marketing",field:"Operações de Campo",last_30_days:"Últimos 30 dias"};
export const reportLabel=(value:unknown)=>value==null||value===""?"Não indicado":labels[String(value)]||String(value).replace(/_/g," ");
export function reportDate(value:unknown){if(!value)return "Não indicada";const d=new Date(String(value));return Number.isNaN(d.getTime())?"Não indicada":new Intl.DateTimeFormat("pt-MZ",{timeZone:"Africa/Maputo",dateStyle:"short",...(String(value).length>10?{timeStyle:"short" as const}:{})}).format(d)}
const amount=(value:unknown)=>value==null?"Não disponível":`${Number(value).toLocaleString("pt-MZ",{minimumFractionDigits:2,maximumFractionDigits:2})} MZN`;
export function reportFilterLines(filters:Record<string,unknown>,range:{from:string;to:string}){
 const out=[`Período: ${reportDate(range.from)} a ${reportDate(range.to)}`];
 for(const [key,label] of [["platform","Plataforma"],["department","Departamento"],["responsible","Responsável"],["status","Estado"]]){const value=filters[key];if(value&&!/^(all|todas?|todos?)$/i.test(String(value)))out.push(`${label}: ${reportLabel(value)}`)}
 if(out.length===1)out.push("Abrangência: todas as plataformas, departamentos, responsáveis e estados autorizados.");return out;
}
export function reportSummaryLines(summary:Record<string,unknown>|null|undefined){
 if(!summary)return ["Resumo indisponível."];
 const out=[`Total de registos: ${Number(summary.total||0)}`,`Pendências: ${Number(summary.pending||0)}`];
 if(!Number(summary.total))out.push("Nenhum registo encontrado no período e nos filtros seleccionados.");
 for(const [key,label] of [["value","Valor total"],["revenue","Receitas"],["expenses","Despesas"],["balance","Saldo do período"]])if(summary[key]!=null)out.push(`${label}: ${amount(summary[key])}`);
 const statuses=Array.isArray(summary.statuses)?summary.statuses as Array<{label:string;value:number}>:[];
 if(statuses.length)out.push("Distribuição por estado:",...statuses.map(row=>`${reportLabel(row.label)}: ${row.value} registo(s)`));return out;
}
export function reportRowValues(row:Record<string,unknown>){return [row.id,reportDate(row.date),row.reference||"Não indicada",row.platform||"Não indicada",reportLabel(row.category),row.value==null?"Não disponível":Number(row.value).toFixed(2),row.currency|| (row.value==null?"":"MZN"),reportLabel(row.status),row.responsible||"Não indicado",row.client||"Não indicado",row.subject||"Não indicado"]}
