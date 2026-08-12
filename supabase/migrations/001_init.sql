-- ==========================================
-- DELIGO - PRODUCTION SCHEMA + RLS
-- ==========================================

-- 1. PROFILES TABLE
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text UNIQUE NOT NULL,
  role text NOT NULL CHECK (role IN ('client', 'restaurant', 'courier')),
  kyc_completed boolean DEFAULT false,
  kyc_docs jsonb DEFAULT '{}'::jsonb,
  kyc_submitted_at timestamptz,
  kyc_rejected_at timestamptz,
  kyc_rejection_reason text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX idx_profiles_auth_id ON profiles(auth_id);
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_profiles_kyc_completed ON profiles(kyc_completed);
-- 2. KYC AUDIT TABLE (rastreamento de todas as aÃ§Ãµes)
CREATE TABLE IF NOT EXISTS kyc_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  action text NOT NULL CHECK (action IN ('submitted', 'approved', 'rejected', 'resubmitted', 'download')),
  payload jsonb,
  actor text, -- 'user', 'admin', 'system'
  actor_id uuid,
  ip_address inet,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX idx_kyc_audit_user_id ON kyc_audit(user_id);
CREATE INDEX idx_kyc_audit_action ON kyc_audit(action);
CREATE INDEX idx_kyc_audit_created_at ON kyc_audit(created_at);
-- ==========================================
-- ROW LEVEL SECURITY (RLS)
-- ==========================================

-- PROFILES: SELECT
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_select_own ON profiles FOR SELECT USING (
  auth.uid() = auth_id OR
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);
CREATE POLICY profiles_update_own ON profiles FOR UPDATE USING (
  auth.uid() = auth_id OR
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);
CREATE POLICY profiles_insert_own ON profiles FOR INSERT WITH CHECK (
  auth.uid() = auth_id
);
-- KYC_AUDIT: SELECT (user vÃª suas aÃ§Ãµes; admin vÃª tudo)
ALTER TABLE kyc_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY kyc_audit_select_own ON kyc_audit FOR SELECT USING (
  user_id IN (SELECT id FROM profiles WHERE auth_id = auth.uid()) OR
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin'
);
CREATE POLICY kyc_audit_insert_admin ON kyc_audit FOR INSERT WITH CHECK (
  (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()) = 'admin' OR
  auth.uid() IS NOT NULL
);
-- ==========================================
-- STORAGE POLICIES (KYC bucket â private)
-- ==========================================

-- Criar bucket 'kyc' manualmente no Supabase console ou via API
-- Depois aplicar policies:

-- UsuÃ¡rio courier pode fazer download de seus prÃ³prios docs
-- (via signed URL gerada pela Edge Function)

-- Admin pode listar e fazer download de todos os docs
-- (via signed URLs geradas por script admin)

-- ==========================================
-- TRIGGERS (auto update updated_at)
-- ==========================================

CREATE OR REPLACE FUNCTION update_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_profiles_updated_at
BEFORE UPDATE ON profiles
FOR EACH ROW
EXECUTE FUNCTION update_profiles_updated_at();
-- ==========================================
-- HELPER FUNCTIONS
-- ==========================================

-- FunÃ§Ã£o para obter o profile do usuÃ¡rio autenticado
CREATE OR REPLACE FUNCTION get_current_profile()
RETURNS TABLE (
  id uuid,
  auth_id uuid,
  name text,
  email text,
  role text,
  kyc_completed boolean,
  kyc_docs jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.auth_id, p.name, p.email, p.role, p.kyc_completed, p.kyc_docs
  FROM profiles p
  WHERE p.auth_id = auth.uid();
END;
$$ LANGUAGE plpgsql;
-- FunÃ§Ã£o para contar documentos KYC jÃ¡ upload ados
CREATE OR REPLACE FUNCTION count_kyc_docs(user_id uuid)
RETURNS int AS $$
DECLARE
  doc_count int;
BEGIN
  SELECT jsonb_object_keys(kyc_docs) INTO doc_count
  FROM profiles
  WHERE id = user_id;
  
  RETURN COALESCE(jsonb_length(
    (SELECT kyc_docs FROM profiles WHERE id = user_id)
  ), 0);
END;
$$ LANGUAGE plpgsql;
