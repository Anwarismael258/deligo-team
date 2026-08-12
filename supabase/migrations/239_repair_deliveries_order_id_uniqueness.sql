BEGIN;
DO $$
BEGIN
  IF to_regclass('public.deliveries') IS NULL THEN
    RETURN;
  END IF;

  -- Mantem apenas a entrega mais recente por pedido antes de impor unicidade.
  WITH ranked AS (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY order_id
        ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
      ) AS row_num
    FROM public.deliveries
    WHERE order_id IS NOT NULL
  )
  DELETE FROM public.deliveries d
  USING ranked r
  WHERE d.id = r.id
    AND r.row_num > 1;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attnum = ANY (c.conkey)
    WHERE c.conrelid = 'public.deliveries'::regclass
      AND c.contype = 'u'
    GROUP BY c.oid
    HAVING array_agg(a.attname::text ORDER BY a.attname::text) =
      ARRAY['order_id']::text[]
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class t
      ON t.oid = i.indrelid
    JOIN pg_namespace n
      ON n.oid = t.relnamespace
    JOIN pg_attribute a
      ON a.attrelid = t.oid
     AND a.attnum = ANY (i.indkey)
    WHERE n.nspname = 'public'
      AND t.relname = 'deliveries'
      AND i.indisunique
    GROUP BY i.indexrelid
    HAVING array_agg(a.attname::text ORDER BY a.attname::text) =
      ARRAY['order_id']::text[]
  ) THEN
    ALTER TABLE public.deliveries
      ADD CONSTRAINT deliveries_order_id_key UNIQUE (order_id);
  END IF;
END $$;
COMMIT;
