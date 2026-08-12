DO $$
BEGIN
  UPDATE public.profiles p
  SET full_name = CASE
        WHEN u.email = 'anwarismael258@gmail.com' THEN 'ANWAR'
        WHEN u.email = 'youngmonster199@gmail.com' THEN 'DELIGO BIKER'
        WHEN u.email = 'anis.justwork@gmail.com' THEN 'Deligo Restaurante'
        ELSE p.full_name
      END,
      avatar_url = CASE
        WHEN u.email = 'anwarismael258@gmail.com' AND COALESCE(NULLIF(p.avatar_url, ''), '') = '' THEN 'https://i.pravatar.cc/300?img=12'
        WHEN u.email = 'youngmonster199@gmail.com' AND COALESCE(NULLIF(p.avatar_url, ''), '') = '' THEN 'https://i.pravatar.cc/300?img=26'
        WHEN u.email = 'anis.justwork@gmail.com' AND COALESCE(NULLIF(p.avatar_url, ''), '') = '' THEN 'https://i.pravatar.cc/300?img=33'
        ELSE p.avatar_url
      END,
      updated_at = NOW()
  FROM auth.users u
  WHERE u.id = p.id
    AND u.email IN (
      'anwarismael258@gmail.com',
      'youngmonster199@gmail.com',
      'anis.justwork@gmail.com'
    );

  UPDATE public.menu_item_reviews mir
  SET reviewer_name = COALESCE(NULLIF(p.full_name, ''), mir.reviewer_name)
  FROM public.profiles p
  WHERE p.id = mir.reviewer_id
    AND COALESCE(NULLIF(p.full_name, '')) IS NOT NULL;

  UPDATE public.courier_reviews cr
  SET reviewer_name = COALESCE(NULLIF(p.full_name, ''), cr.reviewer_name)
  FROM public.profiles p
  WHERE p.id = cr.reviewer_id
    AND COALESCE(NULLIF(p.full_name, '')) IS NOT NULL;
END $$;
