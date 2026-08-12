-- Mestre24 marketplace: catálogo, confiança, urgências e monetização adicional.
-- Executar no Supabase CENTRAL depois da migration de fundação.

alter table mestre24.categories
  add column if not exists parent_id uuid references mestre24.categories(id) on delete restrict,
  add column if not exists description text,
  add column if not exists icon_key text,
  add column if not exists display_order integer not null default 0;

alter table mestre24.professional_profiles
  add column if not exists whatsapp_phone_e164 text,
  add column if not exists service_radius_km integer not null default 10 check (service_radius_km between 1 and 100),
  add column if not exists neighbourhoods text[] not null default '{}',
  add column if not exists available_now boolean not null default false,
  add column if not exists available_24h boolean not null default false,
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_expires_at timestamptz;

create table if not exists mestre24.portfolio_items (
  id uuid primary key default gen_random_uuid(),
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete cascade,
  storage_path text not null,
  caption text,
  work_stage text not null default 'after' check (work_stage in ('before','after','other')),
  display_order smallint not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.reviews (
  id uuid primary key default gen_random_uuid(),
  service_request_id uuid not null references mestre24.service_requests(id) on delete cascade,
  reviewer_user_id uuid not null references mestre24.profiles(user_id) on delete restrict,
  reviewed_user_id uuid not null references mestre24.profiles(user_id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (service_request_id, reviewer_user_id),
  check (reviewer_user_id <> reviewed_user_id)
);

create table if not exists mestre24.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references mestre24.profiles(user_id) on delete restrict,
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete restrict,
  service_request_id uuid references mestre24.service_requests(id) on delete set null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open','validated','dismissed','actioned')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.featured_promotions (
  id uuid primary key default gen_random_uuid(),
  professional_user_id uuid not null references mestre24.professional_profiles(user_id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'MZN',
  provider text check (provider in ('mpesa','emola')),
  provider_reference text unique,
  status text not null default 'pending' check (status in ('pending','paid','active','expired','failed','cancelled')),
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists mestre24.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('in_app','sms','push','whatsapp')),
  template_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','sent','failed','cancelled')),
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function mestre24.ensure_portfolio_limit()
returns trigger language plpgsql as $$
begin
  if (select count(*) from mestre24.portfolio_items where professional_user_id = new.professional_user_id) >= 10 then
    raise exception 'O portfólio Mestre24 permite no máximo 10 fotos.';
  end if;
  return new;
end;
$$;

drop trigger if exists mestre24_portfolio_limit on mestre24.portfolio_items;
create trigger mestre24_portfolio_limit
before insert on mestre24.portfolio_items
for each row execute function mestre24.ensure_portfolio_limit();

-- Após três denúncias validadas, a Central coloca o perfil em suspensão.
create or replace function mestre24.suspend_on_valid_reports()
returns trigger language plpgsql as $$
begin
  if new.status = 'validated' and (tg_op = 'INSERT' or old.status is distinct from 'validated') then
    if (select count(*) from mestre24.reports
        where professional_user_id = new.professional_user_id and status = 'validated') >= 3 then
      update mestre24.professional_profiles
        set verification_status = 'suspended', visible_in_marketplace = false, updated_at = now()
        where user_id = new.professional_user_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists mestre24_suspend_on_valid_reports on mestre24.reports;
create trigger mestre24_suspend_on_valid_reports
after insert or update of status on mestre24.reports
for each row execute function mestre24.suspend_on_valid_reports();

-- Os jobs da Central marcam a subscrição expirada e criam SMS/in-app 3 dias antes.
-- A visibilidade nunca depende apenas do cliente: a view aplica a regra no servidor.
create or replace view mestre24.active_professionals as
select p.user_id, p.full_name, p.city, p.district, pp.headline, pp.biography,
       pp.category_id, pp.rating, pp.review_count, pp.available_now,
       pp.available_24h, pp.service_radius_km, pp.neighbourhoods,
       exists (
         select 1 from mestre24.featured_promotions fp
         where fp.professional_user_id = pp.user_id and fp.status = 'active'
           and fp.starts_at <= now() and fp.expires_at > now()
       ) as is_featured
from mestre24.profiles p
join mestre24.professional_profiles pp on pp.user_id = p.user_id
where p.active = true and pp.visible_in_marketplace = true
  and pp.verification_status = 'approved'
  and (pp.trial_expires_at > now() or pp.subscription_expires_at > now())
  and pp.subscription_status not in ('expired','suspended');

create index if not exists mestre24_categories_parent_idx
  on mestre24.categories(parent_id, display_order) where active = true;
create index if not exists mestre24_available_now_idx
  on mestre24.professional_profiles(category_id, available_now, available_24h)
  where visible_in_marketplace = true;
create index if not exists mestre24_reports_status_idx
  on mestre24.reports(professional_user_id, status, created_at desc);

-- Catálogo oficial de lançamento. Os slugs são a referência estável para apps e Central.
insert into mestre24.categories (name, slug, description, icon_key, display_order) values
  ('Obras e Construção Civil', 'obras-construcao', 'Construção, acabamentos e instalações', 'construction', 10),
  ('Manutenção e Reparações Técnicas', 'manutencao-reparacoes', 'Equipamentos, redes e segurança', 'build', 20),
  ('Serviços Domésticos e Limpeza', 'servicos-domesticos', 'Casa, jardins, piscinas e limpeza', 'cleaning_services', 30),
  ('Automotivo e Transporte', 'automotivo-transporte', 'Viaturas, chaves, fretes e mudanças', 'directions_car', 40),
  ('Estética, Bem-estar e Saúde', 'bem-estar-saude', 'Cuidados pessoais e ao domicílio', 'spa', 50),
  ('Educação, Aulas e Formação', 'educacao-formacao', 'Explicações, idiomas, música e treino', 'school', 60),
  ('Eventos e Festas', 'eventos-festas', 'Comida, imagem, som e decoração', 'celebration', 70),
  ('Serviços Profissionais e Negócios', 'servicos-profissionais', 'Apoio técnico, criativo e administrativo', 'business_center', 80)
on conflict (slug) do update set
  name = excluded.name, description = excluded.description, icon_key = excluded.icon_key,
  display_order = excluded.display_order, active = true;

insert into mestre24.categories (name, slug, parent_id, display_order)
select v.name, v.slug, c.id, v.display_order
from (values
  ('obras-construcao','Mestres de Obra e Pedreiros','mestres-obra-pedreiros',10),
  ('obras-construcao','Pintores','pintores',20), ('obras-construcao','Canalizadores e Encanadores','canalizadores-encanadores',30),
  ('obras-construcao','Eletricistas','eletricistas',40), ('obras-construcao','Carpintores e Marceneiros','carpintores-marceneiros',50),
  ('obras-construcao','Serralheiros','serralheiros',60), ('obras-construcao','Ladrilhadores e Gessistas','ladrilhadores-gessistas',70),
  ('obras-construcao','Vidraceiros','vidraceiros',80), ('manutencao-reparacoes','Climatização (AC)','climatizacao-ac',10),
  ('manutencao-reparacoes','Eletrodomésticos','eletrodomesticos',20), ('manutencao-reparacoes','Segurança Eletrónica','seguranca-eletronica',30),
  ('manutencao-reparacoes','Informática e Redes','informatica-redes',40), ('manutencao-reparacoes','Reparação de Telemóveis','reparacao-telemoveis',50),
  ('manutencao-reparacoes','TV e Antenas','tv-antenas',60), ('servicos-domesticos','Limpeza Doméstica','limpeza-domestica',10),
  ('servicos-domesticos','Limpeza Pós-Obra','limpeza-pos-obra',20), ('servicos-domesticos','Engomadoria','engomadoria',30),
  ('servicos-domesticos','Limpeza de Estofados','limpeza-estofados',40), ('servicos-domesticos','Jardinagem e Paisagismo','jardinagem-paisagismo',50),
  ('servicos-domesticos','Tratamento de Piscinas','tratamento-piscinas',60), ('servicos-domesticos','Desinfestação','desinfestacao',70),
  ('automotivo-transporte','Mecânicos','mecanicos',10), ('automotivo-transporte','Eletricistas Auto','eletricistas-auto',20),
  ('automotivo-transporte','Bate-Chapa e Pintura Auto','bate-chapa-pintura',30), ('automotivo-transporte','Muda-Pneus e Vulcanizadores','vulcanizadores',40),
  ('automotivo-transporte','Chaveiros','chaveiros',50), ('automotivo-transporte','Fretes e Mudanças','fretes-mudancas',60),
  ('bem-estar-saude','Cabeleireiros e Barbeiros','cabeleireiros-barbeiros',10), ('bem-estar-saude','Manicure e Pedicure','manicure-pedicure',20),
  ('bem-estar-saude','Maquilhadores','maquilhadores',30), ('bem-estar-saude','Esteticistas e Depilação','esteticistas-depilacao',40),
  ('bem-estar-saude','Massagistas e Fisioterapeutas','massagistas-fisioterapeutas',50), ('bem-estar-saude','Enfermeiros ao Domicílio','enfermeiros-domicilio',60),
  ('educacao-formacao','Explicações','explicacoes',10), ('educacao-formacao','Aulas de Idiomas','aulas-idiomas',20), ('educacao-formacao','Instrutores de Música','instrutores-musica',30),
  ('educacao-formacao','Personal Trainers','personal-trainers',40), ('eventos-festas','Cozinheiros e Chefs','cozinheiros-chefs',10),
  ('eventos-festas','Pastelaria e Bolos','pastelaria-bolos',20), ('eventos-festas','Fotógrafos e Videógrafos','fotografos-videografos',30),
  ('eventos-festas','DJs e Som','djs-som',40), ('eventos-festas','Decoradores','decoradores',50),
  ('servicos-profissionais','Contabilidade e Fiscalidade','contabilidade-fiscalidade',10), ('servicos-profissionais','Designers Gráficos','designers-graficos',20),
  ('servicos-profissionais','Tradutores e Intérpretes','tradutores-interpretes',30), ('servicos-profissionais','Consultores Jurídicos e Despachantes','consultores-juridicos',40)
) as v(parent_slug, name, slug, display_order)
join mestre24.categories c on c.slug = v.parent_slug
on conflict (slug) do update set name = excluded.name, parent_id = excluded.parent_id,
  display_order = excluded.display_order, active = true;
