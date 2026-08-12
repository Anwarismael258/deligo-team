begin;

-- Institutional publishing is isolated from the HQ operational schema and never grants public write access.
create or replace function public.set_updated_at_v1() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create table if not exists public.news (
 id uuid primary key default gen_random_uuid(), title text not null, slug text not null unique, subtitle text, summary text, content text not null,
 cover_image_url text, video_url text, attachment_url text, category text, platform text not null default 'corporate', author_id uuid, author_name text,
 event_date date, featured boolean not null default false, published boolean not null default false, status text not null default 'draft', scheduled_at timestamptz, published_at timestamptz,
 seo_title text, seo_description text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), approved_at timestamptz, approved_by uuid,
 constraint news_status_check check(status in ('draft','in_review','scheduled','published','archived')),
 constraint news_platform_check check(platform in ('corporate','deligo','sarca','taomoz','comunhao'))
);
create table if not exists public.heroes (id uuid primary key default gen_random_uuid(),title text not null,subtitle text,description text,image_url text,video_url text,button_text text,button_url text,priority integer not null default 0,starts_at timestamptz,ends_at timestamptz,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.job_openings (id uuid primary key default gen_random_uuid(),title text not null,slug text unique,department text,location text,employment_type text,description text,requirements text,benefits text,application_url text,application_email text,deadline date,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.partners (id uuid primary key default gen_random_uuid(),name text not null,description text,logo_url text,website_url text,category text,country text,city text,official boolean not null default false,priority integer not null default 0,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.events (id uuid primary key default gen_random_uuid(),title text not null,slug text unique,description text,image_url text,location text,city text,starts_at timestamptz,ends_at timestamptz,registration_url text,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.team_members (id uuid primary key default gen_random_uuid(),name text not null,role text not null,department text,bio text,photo_url text,linkedin_url text,priority integer not null default 0,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.gallery (id uuid primary key default gen_random_uuid(),title text,caption text,image_url text not null,category text,alt_text text,priority integer not null default 0,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.statistics (id uuid primary key default gen_random_uuid(),key text not null unique,label text not null,value text not null,icon text,priority integer not null default 0,published boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.settings (id uuid primary key default gen_random_uuid(),key text not null unique,value text,group_name text not null default 'site',is_public boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());

create or replace function public.enforce_news_publication_v1() returns trigger language plpgsql as $$
begin
 if new.status='published' then new.published=true; new.published_at=coalesce(new.published_at,now());
 else new.published=false; if new.status='scheduled' and (new.scheduled_at is null or new.scheduled_at<=now()) then raise exception 'CMS_SCHEDULE_MUST_BE_FUTURE'; end if; end if;
 return new;
end $$;
drop trigger if exists trg_news_publication on public.news;
create trigger trg_news_publication before insert or update on public.news for each row execute function public.enforce_news_publication_v1();
do $$ declare t text; begin foreach t in array array['news','heroes','job_openings','partners','events','team_members','gallery','statistics','settings'] loop
 execute format('drop trigger if exists %I on public.%I','trg_'||t||'_updated_at',t); execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at_v1()','trg_'||t||'_updated_at',t); end loop; end $$;

alter table public.news enable row level security; alter table public.heroes enable row level security; alter table public.job_openings enable row level security; alter table public.partners enable row level security; alter table public.events enable row level security; alter table public.team_members enable row level security; alter table public.gallery enable row level security; alter table public.statistics enable row level security; alter table public.settings enable row level security;
drop policy if exists institutional_news_public_read on public.news; create policy institutional_news_public_read on public.news for select to anon using (published=true and (published_at is null or published_at<=now()));
do $$ declare t text; begin foreach t in array array['heroes','job_openings','partners','events','team_members','gallery','statistics'] loop execute format('drop policy if exists %I on public.%I','institutional_'||t||'_public_read',t); execute format('create policy %I on public.%I for select to anon using (published=true)','institutional_'||t||'_public_read',t); end loop; end $$;
drop policy if exists institutional_settings_public_read on public.settings; create policy institutional_settings_public_read on public.settings for select to anon using (is_public=true);
revoke all on public.news,public.heroes,public.job_openings,public.partners,public.events,public.team_members,public.gallery,public.statistics,public.settings from anon;
grant select on public.news,public.heroes,public.job_openings,public.partners,public.events,public.team_members,public.gallery,public.statistics,public.settings to anon;

insert into hq.permissions(code,module,action,data_class,description) values
 ('news.view','news','view','public','Consultar conteúdos institucionais'),('news.create','news','create','public','Criar notícias institucionais'),('news.edit','news','edit','public','Editar notícias institucionais'),('news.review','news','review','public','Rever notícias institucionais'),('news.approve','news','approve','public','Aprovar notícias institucionais'),('news.publish','news','publish','public','Publicar notícias institucionais'),('news.schedule','news','schedule','public','Agendar notícias institucionais'),('news.archive','news','archive','public','Arquivar notícias institucionais'),('news.delete','news','delete','public','Eliminar notícias institucionais'),('news.manage_media','news','manage_media','public','Gerir media institucional')
on conflict(code) do update set module=excluded.module,action=excluded.action,data_class=excluded.data_class,description=excluded.description;
with grants(role_code,permission_code) as (values ('MARKETING','news.view'),('MARKETING','news.create'),('MARKETING','news.edit'),('MARKETING','news.review'),('MARKETING','news.manage_media')) insert into hq.role_permissions(role_id,permission_id) select r.id,p.id from grants g join hq.roles r on r.code=g.role_code join hq.permissions p on p.code=g.permission_code on conflict(role_id,permission_id) do update set effect='allow';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('institutional-news','institutional-news',true,10485760,array['image/jpeg','image/png','image/webp','application/pdf']),('institutional-heroes','institutional-heroes',true,20971520,array['image/jpeg','image/png','image/webp','video/mp4']),('institutional-events','institutional-events',true,10485760,array['image/jpeg','image/png','image/webp']),('institutional-partners','institutional-partners',true,5242880,array['image/jpeg','image/png','image/webp']),('institutional-team','institutional-team',true,5242880,array['image/jpeg','image/png','image/webp']),('institutional-gallery','institutional-gallery',true,10485760,array['image/jpeg','image/png','image/webp']),('institutional-careers','institutional-careers',true,10485760,array['application/pdf','image/jpeg','image/png']) on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
commit;
