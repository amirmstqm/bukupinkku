-- ============================================================================
-- BukuPinkKu — Keselamatan Lapisan Pangkalan Data (RLS + RPC + Rate Limit)
-- Cara guna:
--   1. Buka Supabase Dashboard > SQL Editor > New query
--   2. Tampal keseluruhan skrip ini dan tekan Run
-- ============================================================================

-- 1. Kunci jadual public.families dengan RLS & sekat akses terus daripada anon/authenticated
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'families'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.families', pol.policyname);
  END LOOP;
END $$;

REVOKE ALL ON TABLE public.families FROM anon, authenticated;

-- 2. Jadual dalaman had percubaan gagal di pelayan (anti brute-force)
CREATE TABLE IF NOT EXISTS public.family_auth_attempts (
  invite_code TEXT PRIMARY KEY,
  fail_count INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ
);

ALTER TABLE public.family_auth_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.family_auth_attempts FROM anon, authenticated;

-- 3. RPC Pengesahan Log Masuk Pasangan (Kod Keluarga + 4 Digit Akhir Telefon Isteri)
--    Tidak mendedahkan nombor telefon penuh dan mengunci cubaan salah di pelayan
CREATE OR REPLACE FUNCTION public.verify_family_access(
  p_invite_code TEXT,
  p_phone4 TEXT
)
RETURNS TABLE (
  ret_status TEXT,
  ret_family_id UUID,
  ret_family_name TEXT,
  ret_invite_code TEXT,
  ret_retry_after_seconds INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code TEXT := upper(trim(coalesce(p_invite_code, '')));
  v_phone4 TEXT := regexp_replace(coalesce(p_phone4, ''), '\D', '', 'g');
  v_attempt public.family_auth_attempts%ROWTYPE;
  v_family public.families%ROWTYPE;
  v_extracted_phone TEXT;
BEGIN
  IF v_code = '' OR length(v_phone4) <> 4 THEN
    RETURN QUERY SELECT 'INVALID'::TEXT, NULL::UUID, NULL::TEXT, NULL::TEXT, 0;
    RETURN;
  END IF;

  -- Semak sekatan kadar percubaan pelayan bagi kod ini
  SELECT * INTO v_attempt
  FROM public.family_auth_attempts a
  WHERE a.invite_code = v_code;

  IF FOUND AND v_attempt.locked_until IS NOT NULL AND v_attempt.locked_until > now() THEN
    RETURN QUERY SELECT
      'LOCKED'::TEXT,
      NULL::UUID,
      NULL::TEXT,
      NULL::TEXT,
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_attempt.locked_until - now())))::INT);
    RETURN;
  END IF;

  -- Cari keluarga berdasarkan invite_code
  SELECT * INTO v_family
  FROM public.families f
  WHERE upper(f.invite_code) = v_code
  LIMIT 1;

  IF FOUND THEN
    v_extracted_phone := (regexp_match(coalesce(v_family.family_name, ''), '\[(\d+)\]'))[1];
  ELSE
    v_extracted_phone := NULL;
  END IF;

  -- Padankan 4 digit terakhir nombor telefon ibu berdaftar
  IF FOUND AND v_extracted_phone IS NOT NULL AND right(v_extracted_phone, 4) = v_phone4 THEN
    DELETE FROM public.family_auth_attempts a WHERE a.invite_code = v_code;
    RETURN QUERY SELECT
      'OK'::TEXT,
      v_family.id,
      split_part(coalesce(v_family.family_name, 'Keluarga'), ' [', 1),
      v_family.invite_code,
      0;
    RETURN;
  END IF;

  -- Rekod kegagalan; kunci 5 minit selepas 5 cubaan salah berturut-turut
  INSERT INTO public.family_auth_attempts AS a (invite_code, fail_count, locked_until)
  VALUES (v_code, 1, NULL)
  ON CONFLICT (invite_code) DO UPDATE
  SET
    fail_count = CASE
      WHEN a.locked_until IS NOT NULL AND a.locked_until <= now() THEN 1
      WHEN a.fail_count + 1 >= 5 THEN 0
      ELSE a.fail_count + 1
    END,
    locked_until = CASE
      WHEN a.locked_until IS NOT NULL AND a.locked_until <= now() THEN NULL
      WHEN a.fail_count + 1 >= 5 THEN now() + interval '5 minutes'
      ELSE NULL
    END
  RETURNING * INTO v_attempt;

  IF v_attempt.locked_until IS NOT NULL AND v_attempt.locked_until > now() THEN
    RETURN QUERY SELECT
      'LOCKED'::TEXT,
      NULL::UUID,
      NULL::TEXT,
      NULL::TEXT,
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_attempt.locked_until - now())))::INT);
    RETURN;
  END IF;

  RETURN QUERY SELECT 'INVALID'::TEXT, NULL::UUID, NULL::TEXT, NULL::TEXT, 0;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_family_access(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_family_access(TEXT, TEXT) TO anon, authenticated;

-- 4. RPC Daftar atau Log Masuk Semula Ibu (jana kod unik 6 aksara secara selamat di pelayan)
CREATE OR REPLACE FUNCTION public.register_or_login_mother(
  p_mom_name TEXT,
  p_phone TEXT
)
RETURNS TABLE (
  ret_family_id UUID,
  ret_family_name TEXT,
  ret_invite_code TEXT,
  ret_is_existing BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mom_name TEXT := trim(coalesce(p_mom_name, ''));
  v_clean_phone TEXT := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_family public.families%ROWTYPE;
  v_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_raw TEXT;
  v_suffix TEXT;
  v_new_code TEXT;
  v_idx INT;
  v_attempt INT;
BEGIN
  IF v_clean_phone LIKE '601%' THEN
    v_clean_phone := '0' || substr(v_clean_phone, 3);
  END IF;

  IF v_mom_name = '' THEN
    RAISE EXCEPTION 'INVALID_NAME';
  END IF;

  IF v_clean_phone !~ '^01[0-46-9][0-9]{7,8}$' THEN
    RAISE EXCEPTION 'INVALID_PHONE';
  END IF;

  -- 1. Semak akaun sedia ada berdasarkan no. telefon tepat dalam [...]
  SELECT * INTO v_family
  FROM public.families f
  WHERE position('[' || v_clean_phone || ']' in coalesce(f.family_name, '')) > 0
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY SELECT
      v_family.id,
      split_part(coalesce(v_family.family_name, 'Keluarga'), ' [', 1),
      v_family.invite_code,
      true;
    RETURN;
  END IF;

  -- 2. Semak profil lama yang belum mempunyai no. telefon [...]
  SELECT * INTO v_family
  FROM public.families f
  WHERE lower(trim(coalesce(f.family_name, ''))) = lower('Keluarga ' || v_mom_name)
    AND position('[' in coalesce(f.family_name, '')) = 0
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.families f
    SET family_name = 'Keluarga ' || v_mom_name || ' [' || v_clean_phone || ']'
    WHERE f.id = v_family.id;

    RETURN QUERY SELECT
      v_family.id,
      'Keluarga ' || v_mom_name,
      v_family.invite_code,
      true;
    RETURN;
  END IF;

  -- 3. Daftar keluarga baharu dengan Kod Keluarga rawak 6 aksara alfanumerik
  FOR v_attempt IN 1..10 LOOP
    v_raw := replace(gen_random_uuid()::text, '-', '');
    v_suffix := '';
    FOR i IN 1..6 LOOP
      v_idx := (('x' || substr(v_raw, (i - 1) * 2 + 1, 2))::bit(8)::int % 32) + 1;
      v_suffix := v_suffix || substr(v_alphabet, v_idx, 1);
    END LOOP;
    v_new_code := 'PINK-' || v_suffix;

    IF NOT EXISTS (SELECT 1 FROM public.families f WHERE upper(f.invite_code) = v_new_code) THEN
      BEGIN
        INSERT INTO public.families (family_name, invite_code)
        VALUES ('Keluarga ' || v_mom_name || ' [' || v_clean_phone || ']', v_new_code)
        RETURNING * INTO v_family;

        RETURN QUERY SELECT
          v_family.id,
          'Keluarga ' || v_mom_name,
          v_family.invite_code,
          false;
        RETURN;
      EXCEPTION WHEN unique_violation THEN
        CONTINUE;
      END;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'CODE_GENERATION_FAILED';
END;
$$;

REVOKE ALL ON FUNCTION public.register_or_login_mother(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_or_login_mother(TEXT, TEXT) TO anon, authenticated;
