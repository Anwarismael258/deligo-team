BEGIN;
UPDATE public.orders
SET courier_id = NULL
WHERE courier_id = '451dbfa8-ac31-4376-a9a8-323954ee9b43';
UPDATE public.deliveries
SET courier_id = NULL
WHERE courier_id = '451dbfa8-ac31-4376-a9a8-323954ee9b43';
DELETE FROM auth.users
WHERE id = '451dbfa8-ac31-4376-a9a8-323954ee9b43'
   OR email = 'phone+258825262599@deligo.local';
COMMIT;
