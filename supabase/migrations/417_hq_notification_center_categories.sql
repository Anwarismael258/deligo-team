begin;

alter table hq.notifications add column if not exists category text not null default 'information';
alter table hq.notifications add column if not exists action_required boolean not null default false;
alter table hq.notifications add column if not exists opened_at timestamptz;
alter table hq.notifications add column if not exists channel_policy jsonb not null default '{"central":true}'::jsonb;
alter table hq.notifications drop constraint if exists notifications_category_check;
alter table hq.notifications add constraint notifications_category_check check(category in ('action','approval','task','deadline','alert','information','message','system'));
create index if not exists idx_hq_notifications_action on hq.notifications(employee_id,action_required,read_at,created_at desc);

commit;
