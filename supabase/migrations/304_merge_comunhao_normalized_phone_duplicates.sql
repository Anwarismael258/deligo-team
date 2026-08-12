-- Merge Comunhao users whose legacy phone omitted the leading "+".
-- The pre-existing central identity and password always win.
BEGIN;
DO $merge$
DECLARE
  duplicate_link core.legacy_user_links%ROWTYPE;
  existing_id uuid;
BEGIN
  FOR duplicate_link IN
    SELECT l.*
    FROM core.legacy_user_links l
    JOIN auth.users imported ON imported.id = l.canonical_user_id
    WHERE l.source_app_slug = 'comunhao'
      AND l.source_project_ref = 'dxofxuajsrocbxdmekfx'
      AND l.notes = 'Imported with Comunhao password hash'
      AND length(regexp_replace(coalesce(imported.phone, ''), '\D', '', 'g')) >= 9
  LOOP
    SELECT candidate.id
      INTO existing_id
    FROM auth.users imported
    JOIN auth.users candidate
      ON candidate.id <> imported.id
     AND right(regexp_replace(coalesce(candidate.phone, ''), '\D', '', 'g'), 9)
       = right(regexp_replace(coalesce(imported.phone, ''), '\D', '', 'g'), 9)
    WHERE imported.id = duplicate_link.canonical_user_id
      AND NOT EXISTS (
        SELECT 1
        FROM core.legacy_user_links already_linked
        WHERE already_linked.source_app_slug = 'comunhao'
          AND already_linked.source_project_ref = 'dxofxuajsrocbxdmekfx'
          AND already_linked.canonical_user_id = candidate.id
      )
    ORDER BY candidate.created_at
    LIMIT 1;

    IF existing_id IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO core.profiles (
      user_id, primary_phone, primary_email, full_name, display_name,
      avatar_url, locale, timezone, country_code, default_app_id,
      profile_status, marketing_opt_in, metadata
    )
    SELECT
      existing_id, primary_phone, primary_email, full_name, display_name,
      avatar_url, locale, timezone, country_code, default_app_id,
      profile_status, marketing_opt_in, metadata
    FROM core.profiles
    WHERE user_id = duplicate_link.canonical_user_id
    ON CONFLICT (user_id) DO UPDATE SET
      primary_phone = coalesce(core.profiles.primary_phone, excluded.primary_phone),
      primary_email = coalesce(core.profiles.primary_email, excluded.primary_email),
      full_name = coalesce(core.profiles.full_name, excluded.full_name),
      display_name = coalesce(core.profiles.display_name, excluded.display_name),
      avatar_url = coalesce(core.profiles.avatar_url, excluded.avatar_url),
      default_app_id = excluded.default_app_id,
      metadata = core.profiles.metadata || excluded.metadata,
      updated_at = now();

    INSERT INTO core.user_app_memberships (
      user_id, app_id, membership_status, joined_at, last_seen_at, metadata
    )
    SELECT
      existing_id, app_id, membership_status, joined_at, last_seen_at, metadata
    FROM core.user_app_memberships
    WHERE user_id = duplicate_link.canonical_user_id
      AND app_id = '7b966650-8729-48b4-b2f1-cc1ee11a00f5'::uuid
    ON CONFLICT (user_id, app_id) DO UPDATE SET
      membership_status = 'active',
      metadata = core.user_app_memberships.metadata || excluded.metadata,
      updated_at = now();

    INSERT INTO core.user_roles (
      user_id, role_id, assignment_reason, metadata
    )
    SELECT existing_id, role_id, assignment_reason, metadata
    FROM core.user_roles
    WHERE user_id = duplicate_link.canonical_user_id
    ON CONFLICT (user_id, role_id) DO NOTHING;

    UPDATE core.legacy_user_links
    SET canonical_user_id = existing_id,
        notes = 'Matched central identity by normalized phone; central password preserved',
        updated_at = now()
    WHERE id = duplicate_link.id;

    DELETE FROM core.user_roles
    WHERE user_id = duplicate_link.canonical_user_id;
    DELETE FROM core.user_app_memberships
    WHERE user_id = duplicate_link.canonical_user_id;
    DELETE FROM core.profiles
    WHERE user_id = duplicate_link.canonical_user_id;
    -- The legacy DeliGo auth trigger creates these compatibility rows for
    -- every new auth user. They contain no operational activity at this stage.
    DELETE FROM public.wallets
    WHERE user_id = duplicate_link.canonical_user_id
       OR owner_id = duplicate_link.canonical_user_id;
    DELETE FROM public.profiles
    WHERE user_id = duplicate_link.canonical_user_id;
    DELETE FROM public.users
    WHERE id = duplicate_link.canonical_user_id;
    DELETE FROM auth.identities
    WHERE user_id = duplicate_link.canonical_user_id;
    DELETE FROM auth.users
    WHERE id = duplicate_link.canonical_user_id;
  END LOOP;
END
$merge$;
DO $validation$
DECLARE
  total_users integer;
  link_count integer;
  imported_count integer;
  matched_count integer;
BEGIN
  SELECT count(*) INTO total_users FROM auth.users;
  SELECT
    count(*),
    count(*) FILTER (WHERE notes = 'Imported with Comunhao password hash'),
    count(*) FILTER (WHERE notes LIKE 'Matched central identity%')
  INTO link_count, imported_count, matched_count
  FROM core.legacy_user_links
  WHERE source_app_slug = 'comunhao'
    AND source_project_ref = 'dxofxuajsrocbxdmekfx';

  IF total_users <> 54 OR link_count <> 13
     OR imported_count <> 9 OR matched_count <> 4 THEN
    RAISE EXCEPTION
      'Comunhao merge validation failed: users %, links %, imported %, matched %',
      total_users, link_count, imported_count, matched_count;
  END IF;
END
$validation$;
COMMIT;
