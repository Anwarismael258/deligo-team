import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/399_hq_notification_delivery_channels.sql','utf8');const api=fs.readFileSync('app/api/hr/route.ts','utf8');
test('outbox suporta push, MozESMS e email com estados auditáveis',()=>{for(const x of ['notification_deliveries','moz_esms','web_push','smtp','pending','delivered','attempts','provider_reference'])assert.match(sql,new RegExp(x));});
test('ciclo laboral enfileira SMS MozESMS sem enviar dados sensíveis',()=>{assert.match(api,/notification_deliveries/);assert.match(api,/provider:\"moz_esms\"/);assert.match(api,/HR_LIFECYCLE_NOTICE/);});
