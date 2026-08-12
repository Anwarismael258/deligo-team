begin;
insert into core.apps (
  slug, name, display_name, description, runtime_type, module_schema,
  legacy_project_ref, is_active, is_public
)
values
  ('deligo_admin', 'DeliGo Admin', 'DeliGo Admin',
   'Central operations and platform administration.', 'admin', 'deligo',
   null, true, false),
  ('deligo_marketing', 'DeliGo Marketing', 'DeliGo Marketing',
   'Campaigns, audiences, promotions and engagement operations.', 'admin',
   'deligo', null, true, false),
  ('deligo_field', 'DeliGo Field', 'DeliGo Field',
   'Field onboarding, merchant visits, verification and acquisition.', 'mobile',
   'deligo', null, true, false),
  ('deligo_support', 'DeliGo Support', 'DeliGo Support',
   'Customer, courier, merchant and payment support workflows.', 'admin',
   'deligo', null, true, false),
  ('deligo_web', 'DeliGo Web', 'DeliGo Web',
   'Public DeliGo web commerce experience.', 'web', 'deligo',
   null, true, true),
  ('sarca_admin', 'Sarca Admin', 'Sarca Admin',
   'Sarca mobility administration and safety operations.', 'admin', 'sarca',
   null, true, false),
  ('taomoz_admin', 'TaoMoz Admin', 'TaoMoz Admin',
   'TaoMoz marketplace trust, sellers, catalog and logistics operations.',
   'admin', 'taomoz', null, true, false),
  ('comunhao_admin', 'Comunhao Admin', 'Comunhao Admin',
   'Comunhao platform and church administration.', 'admin', 'comunhao',
   null, true, false)
on conflict (slug) do update set
  name = excluded.name,
  display_name = excluded.display_name,
  description = excluded.description,
  runtime_type = excluded.runtime_type,
  module_schema = excluded.module_schema,
  is_active = excluded.is_active,
  is_public = excluded.is_public,
  updated_at = now();
insert into core.permissions (code, name, module_scope, description)
values
  ('platform.dashboard.read', 'Read platform dashboard', 'platform',
   'View cross-product operational dashboards.'),
  ('platform.settings.manage', 'Manage platform settings', 'platform',
   'Manage central platform configuration.'),
  ('platform.roles.manage', 'Manage roles', 'platform',
   'Assign and revoke staff access.'),
  ('support.case.read', 'Read support cases', 'core',
   'Read customer and partner support cases.'),
  ('support.case.manage', 'Manage support cases', 'core',
   'Create, assign, escalate and resolve support cases.'),
  ('support.user.read', 'Read support-safe user data', 'core',
   'Read the minimum user data required for support.'),
  ('marketing.campaign.read', 'Read campaigns', 'deligo',
   'Read campaigns, audiences and delivery results.'),
  ('marketing.campaign.manage', 'Manage campaigns', 'deligo',
   'Create, approve, schedule and stop campaigns.'),
  ('marketing.audience.manage', 'Manage audiences', 'deligo',
   'Build consent-aware campaign audiences.'),
  ('field.merchant.read', 'Read field merchants', 'deligo',
   'Read merchants assigned to field operations.'),
  ('field.merchant.onboard', 'Onboard merchants', 'deligo',
   'Collect and submit merchant onboarding information.'),
  ('field.visit.manage', 'Manage field visits', 'deligo',
   'Plan, perform and close field visits.'),
  ('deligo.operations.read', 'Read DeliGo operations', 'deligo',
   'Read orders, couriers, merchants and operational events.'),
  ('deligo.operations.manage', 'Manage DeliGo operations', 'deligo',
   'Perform trusted DeliGo operational actions.'),
  ('sarca.operations.read', 'Read Sarca operations', 'sarca',
   'Read trips, drivers and mobility operational data.'),
  ('sarca.operations.manage', 'Manage Sarca operations', 'sarca',
   'Perform trusted Sarca operational actions.'),
  ('taomoz.operations.read', 'Read TaoMoz operations', 'taomoz',
   'Read sellers, products, orders and marketplace risk data.'),
  ('taomoz.operations.manage', 'Manage TaoMoz operations', 'taomoz',
   'Moderate and operate the TaoMoz marketplace.'),
  ('comunhao.operations.read', 'Read Comunhao operations', 'comunhao',
   'Read platform-level Comunhao operational data.'),
  ('comunhao.operations.manage', 'Manage Comunhao operations', 'comunhao',
   'Perform trusted Comunhao platform actions.')
on conflict (code) do update set
  name = excluded.name,
  module_scope = excluded.module_scope,
  description = excluded.description;
insert into core.roles (slug, name, scope, app_id, description)
select seed.slug, seed.name, 'app', app.id, seed.description
from (
  values
    ('deligo_operations_admin', 'DeliGo Operations Admin', 'deligo_admin',
     'Runs DeliGo operational workflows.'),
    ('deligo_support_agent', 'DeliGo Support Agent', 'deligo_support',
     'Handles support cases with restricted user visibility.'),
    ('deligo_support_lead', 'DeliGo Support Lead', 'deligo_support',
     'Supervises support, escalations and sensitive resolutions.'),
    ('deligo_marketing_manager', 'DeliGo Marketing Manager', 'deligo_marketing',
     'Approves campaigns and manages audiences.'),
    ('deligo_marketing_agent', 'DeliGo Marketing Agent', 'deligo_marketing',
     'Creates campaign drafts and reads delivery performance.'),
    ('deligo_field_supervisor', 'DeliGo Field Supervisor', 'deligo_field',
     'Assigns and supervises field operations.'),
    ('deligo_field_agent', 'DeliGo Field Agent', 'deligo_field',
     'Onboards merchants and performs assigned visits.'),
    ('deligo_web_operator', 'DeliGo Web Operator', 'deligo_web',
     'Operates content and commerce exposed on DeliGo Web.'),
    ('sarca_operations_admin', 'Sarca Operations Admin', 'sarca_admin',
     'Runs Sarca driver, safety and trip operations.'),
    ('taomoz_marketplace_admin', 'TaoMoz Marketplace Admin', 'taomoz_admin',
     'Runs marketplace trust, moderation and logistics operations.'),
    ('comunhao_platform_admin', 'Comunhao Platform Admin', 'comunhao_admin',
     'Runs cross-church platform administration.')
) as seed(slug, name, app_slug, description)
join core.apps app on app.slug = seed.app_slug
on conflict (slug) do update set
  name = excluded.name,
  app_id = excluded.app_id,
  description = excluded.description,
  updated_at = now();
with grants(role_slug, permission_code) as (
  values
    ('deligo_operations_admin', 'platform.dashboard.read'),
    ('deligo_operations_admin', 'deligo.operations.read'),
    ('deligo_operations_admin', 'deligo.operations.manage'),
    ('deligo_operations_admin', 'support.case.read'),
    ('deligo_support_agent', 'support.case.read'),
    ('deligo_support_agent', 'support.case.manage'),
    ('deligo_support_agent', 'support.user.read'),
    ('deligo_support_lead', 'support.case.read'),
    ('deligo_support_lead', 'support.case.manage'),
    ('deligo_support_lead', 'support.user.read'),
    ('deligo_support_lead', 'deligo.operations.read'),
    ('deligo_marketing_manager', 'marketing.campaign.read'),
    ('deligo_marketing_manager', 'marketing.campaign.manage'),
    ('deligo_marketing_manager', 'marketing.audience.manage'),
    ('deligo_marketing_agent', 'marketing.campaign.read'),
    ('deligo_field_supervisor', 'field.merchant.read'),
    ('deligo_field_supervisor', 'field.merchant.onboard'),
    ('deligo_field_supervisor', 'field.visit.manage'),
    ('deligo_field_agent', 'field.merchant.read'),
    ('deligo_field_agent', 'field.merchant.onboard'),
    ('deligo_field_agent', 'field.visit.manage'),
    ('deligo_web_operator', 'deligo.operations.read'),
    ('sarca_operations_admin', 'sarca.operations.read'),
    ('sarca_operations_admin', 'sarca.operations.manage'),
    ('taomoz_marketplace_admin', 'taomoz.operations.read'),
    ('taomoz_marketplace_admin', 'taomoz.operations.manage'),
    ('comunhao_platform_admin', 'comunhao.operations.read'),
    ('comunhao_platform_admin', 'comunhao.operations.manage')
)
insert into core.role_permissions (role_id, permission_id)
select r.id, p.id
from grants g
join core.roles r on r.slug = g.role_slug
join core.permissions p on p.code = g.permission_code
on conflict do nothing;
create or replace function core.has_permission(
  p_user_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select
    core.has_role(p_user_id, array['platform_owner', 'platform_admin'])
    or exists (
      select 1
      from core.user_roles ur
      join core.role_permissions rp on rp.role_id = ur.role_id
      join core.permissions p on p.id = rp.permission_id
      where ur.user_id = p_user_id
        and p.code = p_permission_code
        and ur.starts_at <= now()
        and (ur.ends_at is null or ur.ends_at > now())
    );
$$;
create or replace function core.can_access_app(
  p_user_id uuid,
  p_app_slug text
)
returns boolean
language sql
stable
security definer
set search_path = core, public
as $$
  select
    core.has_role(p_user_id, array['platform_owner', 'platform_admin'])
    or exists (
      select 1
      from core.user_app_memberships m
      join core.apps a on a.id = m.app_id
      where m.user_id = p_user_id
        and a.slug = p_app_slug
        and a.is_active
        and m.membership_status = 'active'
    )
    or exists (
      select 1
      from core.user_roles ur
      join core.roles r on r.id = ur.role_id
      join core.apps a on a.id = r.app_id
      where ur.user_id = p_user_id
        and a.slug = p_app_slug
        and ur.starts_at <= now()
        and (ur.ends_at is null or ur.ends_at > now())
    );
$$;
grant execute on function core.has_permission(uuid, text)
  to authenticated, service_role;
grant execute on function core.can_access_app(uuid, text)
  to authenticated, service_role;
notify pgrst, 'reload schema';
commit;
