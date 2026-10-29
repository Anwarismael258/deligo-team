import test from 'node:test';
import assert from 'node:assert/strict';
import {reportFilterLines,reportSummaryLines,reportRowValues,reportColumns} from '../lib/report-presentation.ts';
import {reportPdf} from '../lib/report-export.ts';
import {writeFileSync} from 'node:fs';
test('readable summary preserves missing versus zero values and describes empty results',()=>{
 const lines=reportSummaryLines({total:0,value:null,revenue:0,expenses:0,balance:0,pending:0,statuses:[],metricsUnavailable:[]});
 assert.match(lines.join('\n'),/Nenhum registo/);assert.match(lines.join('\n'),/Receitas: 0/);assert.doesNotMatch(lines.join('\n'),/null|statuses|metricsUnavailable|\{/);
 assert.deepEqual(reportSummaryLines(null),['Resumo indisponível.']);
});
test('filters show actual dates and meaningful Portuguese scope, without serialized config',()=>{
 const lines=reportFilterLines({period:'last_30_days',from:'Todas',platform:'Todas',status:'pending'},{from:'2026-10-01',to:'2026-10-29'});
 assert.match(lines.join('\n'),/Estado: Pendente/);assert.doesNotMatch(lines.join('\n'),/last_30_days|Todas|\{/);
});
test('CSV values have localized status, date and category and preserve full subjects',()=>{
 const values=reportRowValues({id:'x',date:'2026-10-29T05:00:00Z',category:'deposit',value:9.7,status:'confirmed',subject:'Mensagem completa'});
 assert.equal(values[4],'Depósito');assert.equal(values[5],'9.70');assert.equal(values[7],'Confirmado');assert.equal(values[10],'Mensagem completa');assert.equal(reportColumns[8],'Responsável');
});
test('PDF contains readable financial figures instead of JSON',()=>{
 const lines=['Relatório de Finanças',...reportFilterLines({platform:'Todas'},{from:'2026-10-01',to:'2026-10-29'}),...reportSummaryLines({total:2,pending:1,value:19.4,revenue:0,expenses:0,balance:0,statuses:[{label:'confirmed',value:1},{label:'pending',value:1}]})];
 const bytes=reportPdf(lines);writeFileSync(new URL('../tmp/pdfs/readable-report.pdf',import.meta.url),bytes);
 assert.ok(Buffer.from(bytes).includes(Buffer.from('Pendências: 1','latin1')));assert.ok(!Buffer.from(bytes).includes(Buffer.from('"total":')));
});
