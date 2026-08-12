begin;

-- SARCA mobile identities use the existing Conta Triunfal catalog and assignments.
insert into core.apps (slug, name, display_name, description, runtime_type, module_schema, is_active, is_public)
values
  ('sarca_rider', 'SARCA Passageiro', 'SARCA Passageiro', 'Pedido de viagens SARCA.', 'mobile', 'sarca', true, true),
  ('sarca_driver', 'SARCA Motorista', 'SARCA Motorista', 'Operacao de motoristas SARCA.', 'mobile', 'sarca', true, true)
on conflict (slug) do update set display_name = excluded.display_name, description = excluded.description,
  runtime_type = excluded.runtime_type, module_schema = excluded.module_schema, is_active = true, updated_at = now();

insert into core.roles (slug, name, scope, app_id, description)
select seed.slug, seed.name, 'app', app.id, seed.description
from (values
  ('sarca_passenger', 'SARCA Passageiro', 'sarca_rider', 'Permite pedir viagens no SARCA.'),
  ('sarca_driver', 'SARCA Motorista', 'sarca_driver', 'Permite candidatura e operacao de motorista SARCA.')
) as seed(slug, name, app_slug, description)
join core.apps app on app.slug = seed.app_slug
on conflict (slug) do update set name = excluded.name, app_id = excluded.app_id,
  description = excluded.description, updated_at = now();

-- Status belongs to the SARCA driver domain; the role assignment remains canonical in core.user_roles.
create table if not exists sarca.user_role_states (
  user_role_id uuid primary key references core.user_roles(id) on delete cascade,
  status text not null check (status in ('pending', 'active', 'suspended', 'rejected')),
  public_rejection_reason text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function sarca.touch_user_role_state()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists trg_sarca_user_role_state_touch on sarca.user_role_states;
create trigger trg_sarca_user_role_state_touch before update on sarca.user_role_states
for each row execute function sarca.touch_user_role_state();

alter table sarca.user_role_states enable row level security;
drop policy if exists sarca_user_role_states_select_self on sarca.user_role_states;
create policy sarca_user_role_states_select_self on sarca.user_role_states for select to authenticated
using (exists (select 1 from core.user_roles ur where ur.id = user_role_id and ur.user_id = auth.uid()));
revoke insert, update, delete on sarca.user_role_states from authenticated;

-- Only the authenticated owner can create an application role. Driver status is always pending.
create or replace function sarca.activate_my_role(p_role_slug text)
returns table (role_slug text, status text)
language plpgsql security definer set search_path = sarca, core, public, pg_temp as $$
declare v_user_id uuid := auth.uid(); v_role_id uuid; v_assignment_id uuid; v_app_id uuid; v_status text;
begin
  if v_user_id is null then raise exception 'Unauthorized'; end if;
  if p_role_slug not in ('sarca_passenger', 'sarca_driver') then raise exception 'Invalid SARCA role'; end if;
  select r.id, r.app_id into v_role_id, v_app_id from core.roles r where r.slug = p_role_slug;
  if v_role_id is null then raise exception 'SARCA role catalog is unavailable'; end if;
  insert into core.user_app_memberships(user_id, app_id, membership_status)
  values (v_user_id, v_app_id, 'active') on conflict (user_id, app_id) do update set last_seen_at = now();
  insert into core.user_roles(user_id, role_id, assignment_reason)
  values (v_user_id, v_role_id, 'self_service_sarca_onboarding')
  on conflict (user_id, role_id) do update set ends_at = null, updated_at = now()
  returning id into v_assignment_id;
  if v_assignment_id is null then select id into v_assignment_id from core.user_roles where user_id=v_user_id and role_id=v_role_id; end if;
  if p_role_slug = 'sarca_driver' then
    insert into sarca.user_role_states(user_role_id, status) values (v_assignment_id, 'pending') on conflict do nothing;
  else
    insert into sarca.user_role_states(user_role_id, status) values (v_assignment_id, 'active') on conflict do nothing;
  end if;
  select s.status into v_status from sarca.user_role_states s where s.user_role_id=v_assignment_id;
  return query select p_role_slug, coalesce(v_status, 'active');
end $$;
revoke all on function sarca.activate_my_role(text) from public;
grant execute on function sarca.activate_my_role(text) to authenticated;

commit;
