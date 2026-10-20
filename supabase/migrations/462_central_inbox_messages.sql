-- Caixa de entrada da Central: mensagens públicas do site.
create table if not exists public.central_area_roles (
  area text not null check (area in ('geral','comercial','carreiras','noticias')),
  role text not null,
  primary key (area, role)
);
revoke all on public.central_area_roles from anon;
grant select on public.central_area_roles to authenticated;
grant all on public.central_area_roles to service_role;
alter table public.central_area_roles enable row level security;
drop policy if exists "area roles readable" on public.central_area_roles;
create policy "area roles readable" on public.central_area_roles for select to authenticated using (true);
insert into public.central_area_roles(area, role) values
  ('geral','admin'), ('geral','supervisor'), ('geral','suporte'),
  ('comercial','admin'), ('comercial','supervisor'), ('comercial','marketing'),
  ('carreiras','admin'), ('carreiras','supervisor'),
  ('noticias','admin'), ('noticias','supervisor'), ('noticias','marketing'), ('noticias','financas')
on conflict do nothing;
create or replace function public.has_area_access(_area text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles r join public.central_area_roles a on a.role = r.role::text where r.user_id = auth.uid() and a.area = _area)
$$;
grant execute on function public.has_area_access(text) to authenticated;

create table if not exists public.inbox_messages (
  id uuid primary key default gen_random_uuid(), area text not null check (area in ('geral','comercial','carreiras')),
  source text not null check (source in ('site_contacto','site_candidatura','email')),
  subject text not null, from_name text not null, from_email text not null, phone text, company text,
  body text not null, meta jsonb not null default '{}'::jsonb, external_id text unique,
  status text not null default 'novo' check (status in ('novo','em_tratamento','respondido','fechado','spam')),
  assigned_to uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
revoke all on public.inbox_messages from anon;
grant select, update on public.inbox_messages to authenticated;
grant all on public.inbox_messages to service_role;
alter table public.inbox_messages enable row level security;
drop policy if exists "inbox staff read" on public.inbox_messages;
create policy "inbox staff read" on public.inbox_messages for select to authenticated using (public.has_area_access(area));
drop policy if exists "inbox staff update" on public.inbox_messages;
create policy "inbox staff update" on public.inbox_messages for update to authenticated using (public.has_area_access(area)) with check (public.has_area_access(area));

create table if not exists public.inbox_replies (
  id uuid primary key default gen_random_uuid(), message_id uuid not null references public.inbox_messages(id) on delete cascade,
  author_id uuid not null default auth.uid() references auth.users(id), kind text not null check (kind in ('resposta','nota')),
  body text not null check (length(trim(body)) between 1 and 10000), send_status text not null default 'pendente' check (send_status in ('pendente','enviado','falhou','n/a')),
  send_error text, created_at timestamptz not null default now()
);
revoke all on public.inbox_replies from anon;
grant select, insert on public.inbox_replies to authenticated;
grant all on public.inbox_replies to service_role;
alter table public.inbox_replies enable row level security;
drop policy if exists "replies staff read" on public.inbox_replies;
create policy "replies staff read" on public.inbox_replies for select to authenticated using (exists (select 1 from public.inbox_messages m where m.id = message_id and public.has_area_access(m.area)));
drop policy if exists "replies staff insert" on public.inbox_replies;
create policy "replies staff insert" on public.inbox_replies for insert to authenticated with check (author_id = auth.uid() and exists (select 1 from public.inbox_messages m where m.id = message_id and public.has_area_access(m.area)));

create or replace function public.submit_inbox_message(p_area text, p_source text, p_subject text, p_from_name text, p_from_email text, p_phone text, p_company text, p_body text, p_meta jsonb default '{}'::jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text := lower(trim(p_from_email));
begin
  if p_area not in ('geral','comercial','carreiras') then raise exception 'area invalida'; end if;
  if p_source not in ('site_contacto','site_candidatura') then raise exception 'origem invalida'; end if;
  if length(trim(coalesce(p_from_name,''))) not between 1 and 100 then raise exception 'nome invalido'; end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 254 then raise exception 'email invalido'; end if;
  if length(trim(coalesce(p_subject,''))) not between 1 and 200 then raise exception 'assunto invalido'; end if;
  if length(trim(coalesce(p_body,''))) > 3000 then raise exception 'mensagem longa'; end if;
  if length(coalesce(p_phone,'')) > 30 or length(coalesce(p_company,'')) > 150 then raise exception 'texto longo'; end if;
  if pg_column_size(p_meta) > 2000 then raise exception 'meta longa'; end if;
  if (select count(*) from inbox_messages where from_email = v_email and created_at > now() - interval '1 hour') >= 5 then raise exception 'limite: muitas mensagens'; end if;
  insert into inbox_messages(area, source, subject, from_name, from_email, phone, company, body, meta)
  values (p_area, p_source, trim(p_subject), trim(p_from_name), v_email, nullif(trim(p_phone),''), nullif(trim(p_company),''), coalesce(nullif(trim(p_body),''), '(sem mensagem)'), coalesce(p_meta,'{}'::jsonb)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.submit_inbox_message from public;
grant execute on function public.submit_inbox_message to anon, authenticated;
create or replace function public.inbox_touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists inbox_touch on public.inbox_messages;
create trigger inbox_touch before update on public.inbox_messages for each row execute function public.inbox_touch();
