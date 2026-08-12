-- 039_enums_modernize.sql
-- Modernize enums safely (only additive changes, no destructive renames).

BEGIN;
-- 1) wallet_owner_type: add 'customer' if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'wallet_owner_type' AND e.enumlabel = 'customer'
  ) THEN
    ALTER TYPE public.wallet_owner_type ADD VALUE IF NOT EXISTS 'customer';
  END IF;
END $$;
-- 2) transaction_category: add 'refund' and 'bonus' if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'transaction_category' AND e.enumlabel = 'refund'
  ) THEN
    ALTER TYPE public.transaction_category ADD VALUE IF NOT EXISTS 'refund';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typname = 'transaction_category' AND e.enumlabel = 'bonus'
  ) THEN
    ALTER TYPE public.transaction_category ADD VALUE IF NOT EXISTS 'bonus';
  END IF;
END $$;
-- 3) delivery_status: create if not exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'delivery_status') THEN
    CREATE TYPE public.delivery_status AS ENUM (
      'pending',
      'picked_up',
      'delivering',
      'delivered'
    );
  END IF;
END $$;
COMMIT;
