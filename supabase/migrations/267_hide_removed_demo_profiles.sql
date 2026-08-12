BEGIN;
WITH target_restaurants AS (
  SELECT id, owner_id
  FROM public.restaurants
  WHERE lower(coalesce(name, '')) LIKE '%txapita%'
     OR lower(coalesce(name, '')) LIKE '%matafome%'
     OR lower(coalesce(name, '')) LIKE '%walter vlk%'
     OR (
       lower(coalesce(name, '')) LIKE '%walter%'
       AND lower(coalesce(name, '')) LIKE '%vlk%'
     )
)
UPDATE public.restaurants r
SET is_open = FALSE,
    name = 'Perfil removido',
    description = 'Perfil removido pela administracao DeliGo.',
    image_url = NULL,
    updated_at = now()
FROM target_restaurants t
WHERE r.id = t.id;
WITH target_profiles AS (
  SELECT p.id
  FROM public.profiles p
  LEFT JOIN public.restaurants r ON r.owner_id = p.id
  WHERE lower(coalesce(p.full_name, '')) LIKE '%txapita%'
     OR lower(coalesce(p.full_name, '')) LIKE '%matafome%'
     OR lower(coalesce(p.full_name, '')) LIKE '%walter vlk%'
     OR (
       lower(coalesce(p.full_name, '')) LIKE '%walter%'
       AND lower(coalesce(p.full_name, '')) LIKE '%vlk%'
     )
     OR lower(coalesce(r.name, '')) IN ('perfil removido')
)
UPDATE public.profiles p
SET full_name = 'Perfil removido',
    is_blocked = TRUE,
    block_reason = 'Perfil removido pela administracao DeliGo.',
    updated_at = now()
FROM target_profiles t
WHERE p.id = t.id;
COMMIT;
