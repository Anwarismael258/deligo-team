begin;

-- A marca corporativa passa a ser uma plataforma seleccionável nas campanhas,
-- sem duplicar a aplicação nem retirar as plataformas operacionais existentes.
insert into hq.platforms (legal_entity_id, slug, name, schema_name)
values ('10000000-0000-0000-0000-000000000001', 'corporate', 'DeliGo Triunfal / Corporativo', 'corporate')
on conflict (slug) do update set name = excluded.name, schema_name = excluded.schema_name;

alter table hq.marketing_campaigns add column if not exists objective_code text;
alter table hq.marketing_campaigns add column if not exists audience_filters jsonb not null default '{}'::jsonb;
alter table hq.marketing_campaigns add column if not exists committed_amount numeric(18,2) not null default 0 check (committed_amount >= 0);

create index if not exists idx_marketing_campaigns_status_dates
  on hq.marketing_campaigns(status, starts_at, ends_at);

commit;
