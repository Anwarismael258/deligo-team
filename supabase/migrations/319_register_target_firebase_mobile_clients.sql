begin;
-- Target Firebase mobile clients. They stay planned until each Android
-- applicationId is migrated and the release passes Firebase smoke tests.
insert into core.mobile_app_clients (
  app_id, client_slug, platform, package_name, firebase_project_id,
  firebase_app_id, status, metadata
)
select app.id, seed.client_slug, 'android', seed.package_name,
  'deligo-triunfal-lda', seed.firebase_app_id, 'planned',
  jsonb_build_object('source', 'target_google_services', 'migration_required', true)
from (
  values
    ('comunhao', 'comunhao_churches_target', 'comunhao.igrejas', '1:12765576072:android:7f70e76a88006826d0583d'),
    ('comunhao', 'comunhao_members_target', 'comunhao.membros', '1:12765576072:android:1454d6894aaf941ad0583d'),
    ('deligo', 'deligo_delivery_target', 'deligo.delivery', '1:12765576072:android:eff93d94a6d4ca5dd0583d'),
    ('taomoz', 'taomoz_android_target', 'deligo.taomoz', '1:12765576072:android:716af11f78fc9001d0583d'),
    ('sarca', 'sarca_driver_target', 'sarca.driver', '1:12765576072:android:61671ca881946b66d0583d'),
    ('sarca', 'sarca_rider_target', 'sarca.rider', '1:12765576072:android:f411ec9f00ed806bd0583d')
) as seed(app_slug, client_slug, package_name, firebase_app_id)
join core.apps app on app.slug = seed.app_slug
on conflict (client_slug) do update
set package_name = excluded.package_name,
    firebase_project_id = excluded.firebase_project_id,
    firebase_app_id = excluded.firebase_app_id,
    status = excluded.status,
    metadata = excluded.metadata,
    updated_at = now();
commit;
