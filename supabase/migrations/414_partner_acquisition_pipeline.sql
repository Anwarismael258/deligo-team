begin;

alter table hq.acquisition_leads add column if not exists partner_category text;
alter table hq.acquisition_leads add column if not exists acquisition_channel text;
alter table hq.acquisition_leads add column if not exists conversion_probability numeric(5,2) check (conversion_probability is null or conversion_probability between 0 and 100);
alter table hq.acquisition_leads add column if not exists next_action text;
alter table hq.acquisition_leads add column if not exists loss_reason text;
alter table hq.acquisition_leads add column if not exists kyc_status text not null default 'not_started' check (kyc_status in ('not_started','pending','in_review','correction_requested','approved','rejected','escalated'));

insert into hq.permissions(code,module,action,data_class,description) values
 ('partner.lead.view','acquisition','lead_view','confidential','Consultar leads de parceiros'),
 ('partner.lead.create','acquisition','lead_create','confidential','Criar leads de parceiros'),
 ('partner.lead.assign','acquisition','lead_assign','confidential','Atribuir leads de parceiros'),
 ('partner.negotiate','acquisition','negotiate','confidential','Gerir negociações'),
 ('partner.convert','acquisition','convert','confidential','Iniciar onboarding de parceiro'),
 ('partner.admin','acquisition','admin','confidential','Administrar aquisição de parceiros')
on conflict(code) do update set description=excluded.description;

create index if not exists idx_acquisition_leads_kyc on hq.acquisition_leads(kyc_status,platform_id,updated_at desc);

commit;
