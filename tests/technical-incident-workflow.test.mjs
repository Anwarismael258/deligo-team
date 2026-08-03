import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const read=(path)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");

test("incidentes técnicos aparecem na Visão Geral sem dados simulados",async()=>{
  const[api,component,page]=await Promise.all([read("app/api/operational-alerts/route.ts"),read("app/components/TechnicalIncidentAlerts.tsx"),read("app/page.tsx")]);
  assert.match(api,/status=not\.in\.\(resolved,closed\)/);
  assert.match(api,/corporateActor\(\)/);
  assert.match(component,/setInterval\(\(\)=>void refresh\(\),10000\)/);
  assert.match(component,/não inventa um estado/);
  assert.match(page,/TechnicalIncidentAlerts/);
});

test("resolução final cria relatório técnico persistente e auditado",async()=>{
  const[workflow,migration,technology]=await Promise.all([read("app/api/workflows/route.ts"),read("supabase/migrations/371_hq_technical_incident_reports.sql"),read("app/api/technology/route.ts")]);
  assert.match(workflow,/incident_resolution_report/);
  assert.match(workflow,/technology_failure_history/);
  assert.match(workflow,/technical_incident_report_created/);
  assert.match(migration,/create table if not exists hq\.technology_incident_reports/);
  assert.match(migration,/enable row level security/);
  assert.match(migration,/revoke all .* from public,anon,authenticated/);
  assert.match(technology,/technology_incident_reports\?select=/);
});
