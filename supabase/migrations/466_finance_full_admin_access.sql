begin;

-- FINANCE is the Central's deputy administrator: it must have the same
-- effective permissions and platform scope as SUPER_ADMIN.
create or replace function hq.is_full_admin_employee(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path=hq,public,pg_temp
as $$
  select exists(
    select 1
    from hq.employee_roles er
    join hq.roles r on r.id=er.role_id
    where er.employee_id=p_employee_id
      and r.code in ('SUPER_ADMIN','FINANCE')
      and r.active
      and er.revoked_at is null
      and (er.valid_until is null or er.valid_until>now())
  )
$$;

revoke all on function hq.is_full_admin_employee(uuid) from public,anon,authenticated;
grant execute on function hq.is_full_admin_employee(uuid) to service_role;

-- Keep the role matrix complete as well as the global-admin fast path. This
-- helps callers that inspect role_permissions directly.
insert into hq.role_permissions(role_id,permission_id,effect)
select r.id,p.id,'allow'
from hq.roles r
cross join hq.permissions p
where r.code='FINANCE'
on conflict(role_id,permission_id) do update set effect='allow';

create or replace function public.hq_actor_authorization_v1(p_employee_id uuid) returns jsonb
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  is_super boolean;
  permission_codes text[];
  platform_ids uuid[];
  platform_slugs text[];
begin
  if not exists(select 1 from hq.employees where id=p_employee_id and status='active') then
    raise exception 'HQ_ACTOR_INACTIVE';
  end if;

  is_super := hq.is_full_admin_employee(p_employee_id);

  select coalesce(array_agg(code order by code),'{}'::text[])
  into permission_codes
  from (
    select p.code from hq.permissions p where is_super
    union
    select p.code
    from hq.employee_roles er
    join hq.roles r on r.id=er.role_id and r.active
    join hq.role_permissions rp on rp.role_id=r.id and rp.effect='allow'
    join hq.permissions p on p.id=rp.permission_id
    where er.employee_id=p_employee_id
      and er.revoked_at is null
      and (er.valid_until is null or er.valid_until>now())
    union
    select o.permission_code
    from hq.employee_permission_overrides o
    where o.employee_id=p_employee_id and o.allowed
    except
    select o.permission_code
    from hq.employee_permission_overrides o
    where o.employee_id=p_employee_id and not o.allowed and not is_super
  ) q;

  if is_super then
    select coalesce(array_agg(id order by slug),'{}'::uuid[]),
           coalesce(array_agg(slug order by slug),'{}'::text[])
    into platform_ids,platform_slugs
    from hq.platforms
    where status='active';
  else
    select coalesce(array_agg(p.id order by p.slug),'{}'::uuid[]),
           coalesce(array_agg(p.slug order by p.slug),'{}'::text[])
    into platform_ids,platform_slugs
    from hq.employee_platforms ep
    join hq.platforms p on p.id=ep.platform_id and p.status='active'
    where ep.employee_id=p_employee_id
      and ep.revoked_at is null
      and (ep.valid_until is null or ep.valid_until>now());
  end if;

  return jsonb_build_object(
    'is_super_admin',is_super,
    'permissions',permission_codes,
    'platform_ids',platform_ids,
    'platform_slugs',platform_slugs
  );
end
$$;

revoke all on function public.hq_actor_authorization_v1(uuid) from public,anon,authenticated;
grant execute on function public.hq_actor_authorization_v1(uuid) to service_role;

-- The event notification router must use the same global-admin definition so
-- Finance receives platform-wide events, not just finance-tagged events.
create or replace function hq.notify_permissioned_event(
  p_event_key text,
  p_type text,
  p_title text,
  p_body text,
  p_platform_id uuid,
  p_target_url text,
  p_required_permissions text[],
  p_category text,
  p_action_required boolean,
  p_priority text,
  p_origin_department_id uuid,
  p_source_type text,
  p_source_id text
) returns integer
language plpgsql
security definer
set search_path=hq,public,pg_temp
as $$
declare
  inserted_count integer := 0;
  permission_codes text[] := coalesce(nullif(p_required_permissions,'{}'::text[]),array['platforms.view']::text[]);
begin
  if coalesce(trim(p_event_key),'') = '' then return 0; end if;

  insert into hq.notifications(
    employee_id,type,title,body,platform_id,target_url,
    origin_department_id,priority,responsible_employee_id,
    source_type,source_id,dedupe_key,category,action_required,channel_policy
  )
  select
    e.id,
    coalesce(nullif(p_type,''),'information'),
    p_title,
    p_body,
    p_platform_id,
    coalesce(nullif(p_target_url,''),'/'),
    p_origin_department_id,
    coalesce(nullif(p_priority,''),'normal'),
    e.id,
    p_source_type,
    p_source_id,
    p_event_key||':'||e.id::text,
    case when p_category in ('action','approval','task','deadline','alert','information','message','system') then p_category else 'information' end,
    coalesce(p_action_required,false),
    jsonb_build_object('central',true)
  from hq.employees e
  where e.status='active'
    and (
      hq.is_full_admin_employee(e.id)
      or exists(
        select 1
        from unnest(permission_codes) required(code)
        where not exists(
          select 1 from hq.employee_permission_overrides denied
          where denied.employee_id=e.id
            and denied.permission_code=required.code
            and denied.allowed=false
        )
        and (
          exists(
            select 1
            from hq.employee_roles er
            join hq.roles r on r.id=er.role_id and r.active
            join hq.role_permissions rp on rp.role_id=r.id and rp.effect='allow'
            join hq.permissions p on p.id=rp.permission_id and p.code=required.code
            where er.employee_id=e.id
              and er.revoked_at is null
              and (er.valid_until is null or er.valid_until>now())
          )
          or exists(
            select 1 from hq.employee_permission_overrides allowed
            where allowed.employee_id=e.id
              and allowed.permission_code=required.code
              and allowed.allowed=true
          )
        )
      )
    )
    and (
      p_platform_id is null
      or hq.is_full_admin_employee(e.id)
      or exists(
        select 1 from hq.employee_platforms ep
        where ep.employee_id=e.id
          and ep.platform_id=p_platform_id
          and ep.revoked_at is null
          and (ep.valid_until is null or ep.valid_until>now())
      )
    )
  on conflict(employee_id,dedupe_key) where dedupe_key is not null do nothing;

  get diagnostics inserted_count=row_count;
  return inserted_count;
end
$$;

revoke all on function hq.notify_permissioned_event(text,text,text,text,uuid,text,text[],text,boolean,text,uuid,text,text) from public,anon,authenticated;
grant execute on function hq.notify_permissioned_event(text,text,text,text,uuid,text,text[],text,boolean,text,uuid,text,text) to service_role;

commit;
