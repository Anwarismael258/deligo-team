-- Migration: Adicionar suporte a FCM tokens e notificações
-- Executar após 001_init.sql

-- 1. Adicionar coluna fcm_token à tabela profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token_updated_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_profiles_fcm_token ON profiles(fcm_token);
-- 2. Criar tabela de notificações (histórico)
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  type text CHECK (type IN ('kyc_approved', 'kyc_rejected', 'order_update', 'system')) NOT NULL,
  data jsonb DEFAULT '{}'::jsonb,
  sent_at timestamptz DEFAULT now(),
  read_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at);
-- 3. Trigger para limpar FCM tokens antigos (auto cleanup)
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS void AS $$
BEGIN
  DELETE FROM notifications
  WHERE created_at < now() - interval '90 days';
END;
$$ LANGUAGE plpgsql;
-- 4. RLS para notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notifications_select_own ON notifications FOR SELECT USING (
  user_id IN (SELECT id FROM profiles WHERE auth_id = auth.uid()) OR
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);
CREATE POLICY notifications_insert_admin ON notifications FOR INSERT WITH CHECK (
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);
