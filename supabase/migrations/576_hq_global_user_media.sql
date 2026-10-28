-- Expose the canonical profile avatar to the HQ directory view.
-- This is read-only presentation data; it does not change access rules or
-- expose private document paths. Private media is still resolved by the
-- authenticated profile-detail route through signed storage URLs.
create or replace view hq.global_user_platforms_v1 as
select
  p.user_id,
  p.full_name,
  p.display_name,
  p.primary_phone,
  p.primary_email,
  p.avatar_url,
  p.profile_status,
  a.slug as app_slug,
  a.display_name as app_name,
  m.membership_status,
  m.joined_at,
  m.last_seen_at,
  coalesce(jsonb_agg(distinct r.slug) filter (where r.slug is not null), '[]'::jsonb) as roles
from core.profiles p
left join core.user_app_memberships m on m.user_id = p.user_id
left join core.apps a on a.id = m.app_id
left join core.user_roles ur on ur.user_id = p.user_id
  and ur.starts_at <= now()
  and (ur.ends_at is null or ur.ends_at > now())
left join core.roles r on r.id = ur.role_id
  and (r.app_id is null or r.app_id = a.id)
group by
  p.user_id,
  p.full_name,
  p.display_name,
  p.primary_phone,
  p.primary_email,
  p.avatar_url,
  p.profile_status,
  a.slug,
  a.display_name,
  m.membership_status,
  m.joined_at,
  m.last_seen_at;

grant select on hq.global_user_platforms_v1 to service_role;
