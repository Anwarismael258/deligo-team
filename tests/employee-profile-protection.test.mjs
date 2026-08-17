import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/400_hq_employee_profile_protection.sql','utf8');
test('separa perfil editável do employee record oficial',()=>{assert.match(sql,/employee_display_profiles/);assert.match(sql,/employee_id uuid primary key/);assert.match(sql,/Self-service fields only/);});
test('wallet exige confirmação e mantém histórico',()=>{for(const x of ['employee_wallet_change_requests','otp_pending','new_number_hash','confirmed_at','ip_address','device_reference','employee_wallet_change_history','wallet_number_changed_at'])assert.match(sql,new RegExp(x));});
