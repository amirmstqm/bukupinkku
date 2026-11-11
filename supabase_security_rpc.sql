-- ============================================================================
-- BukuPinkKu — Keselamatan Penuh Pangkalan Data (RLS + RPC + Token Sesi)
-- Cara guna:
--   1. Buka Supabase Dashboard > SQL Editor > New query
--   2. Tampal keseluruhan skrip ini dan tekan Run
-- ============================================================================

-- 1. Tambah token sesi rahsia bagi setiap keluarga dalam public.families
ALTER TABLE public.families
  ADD COLUMN IF NOT EXISTS access_token TEXT;

UPDATE public.families
SET access_token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
WHERE access_token IS NULL OR trim(access_token) = '';

ALTER TABLE public.families
  ALTER COLUMN access_token SET DEFAULT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');

-- 2. Kunci jadual public.families, family_auth_attempts, feedbacks, dan 5 jadual kesihatan
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.family_auth_attempts (
  invite_code TEXT PRIMARY KEY,
  fail_count INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ
);
ALTER TABLE public.family_auth_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.family_auth_attempts FROM anon, authenticated;

DO $$
DECLARE
  tbl TEXT;
  pol RECORD;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['families', 'children', 'appointments', 'health_vitals', 'allergies', 'baby_memories', 'feedbacks']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
    FOR pol IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, tbl);
    END LOOP;
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', tbl);
  END LOOP;
END $$;

-- Feedbacks hanya dibenarkan INSERT oleh pengguna awam (tiada SELECT/UPDATE/DELETE)
GRANT INSERT ON TABLE public.feedbacks TO anon, authenticated;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

CREATE POLICY "Allow anon insert feedbacks only"
  ON public.feedbacks
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- 3. Fungsi pembantu dalaman untuk sahkan (family_id + access_token)
CREATE OR REPLACE FUNCTION public._verify_family_token(
  p_family_id UUID,
  p_access_token TEXT,
  p_allow_demo_read BOOLEAN DEFAULT false
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (p_allow_demo_read AND p_family_id = 'a0000000-0000-0000-0000-000000000001'::uuid)
    OR EXISTS (
      SELECT 1
      FROM public.families f
      WHERE f.id = p_family_id
        AND p_family_id <> 'a0000000-0000-0000-0000-000000000001'::uuid
        AND f.access_token IS NOT NULL
        AND f.access_token = nullif(trim(coalesce(p_access_token, '')), '')
    );
$$;

REVOKE ALL ON FUNCTION public._verify_family_token(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- 4. RPC Pengesahan Log Masuk Pasangan (Kod Keluarga + 4 Digit Akhir Telefon Isteri)
DROP FUNCTION IF EXISTS public.verify_family_access(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.verify_family_access(
  p_invite_code TEXT,
  p_phone4 TEXT
)
RETURNS TABLE (
  ret_status TEXT,
  ret_family_id UUID,
  ret_family_name TEXT,
  ret_invite_code TEXT,
  ret_retry_after_seconds INT,
  ret_access_token TEXT
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
    RETURN QUERY SELECT 'INVALID'::TEXT, NULL::UUID, NULL::TEXT, NULL::TEXT, 0, NULL::TEXT;
    RETURN;
  END IF;

  SELECT * INTO v_attempt
  FROM public.family_auth_attempts a
  WHERE a.invite_code = v_code;

  IF FOUND AND v_attempt.locked_until IS NOT NULL AND v_attempt.locked_until > now() THEN
    RETURN QUERY SELECT
      'LOCKED'::TEXT,
      NULL::UUID,
      NULL::TEXT,
      NULL::TEXT,
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_attempt.locked_until - now())))::INT),
      NULL::TEXT;
    RETURN;
  END IF;

  SELECT * INTO v_family
  FROM public.families f
  WHERE upper(f.invite_code) = v_code
  LIMIT 1;

  IF FOUND THEN
    v_extracted_phone := (regexp_match(coalesce(v_family.family_name, ''), '\[(\d+)\]'))[1];
  ELSE
    v_extracted_phone := NULL;
  END IF;

  IF FOUND AND v_extracted_phone IS NOT NULL AND right(v_extracted_phone, 4) = v_phone4 THEN
    IF v_family.access_token IS NULL OR trim(v_family.access_token) = '' THEN
      UPDATE public.families f
      SET access_token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
      WHERE f.id = v_family.id
      RETURNING * INTO v_family;
    END IF;

    DELETE FROM public.family_auth_attempts a WHERE a.invite_code = v_code;
    RETURN QUERY SELECT
      'OK'::TEXT,
      v_family.id,
      split_part(coalesce(v_family.family_name, 'Keluarga'), ' [', 1),
      v_family.invite_code,
      0,
      v_family.access_token;
    RETURN;
  END IF;

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
      GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_attempt.locked_until - now())))::INT),
      NULL::TEXT;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'INVALID'::TEXT, NULL::UUID, NULL::TEXT, NULL::TEXT, 0, NULL::TEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.verify_family_access(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_family_access(TEXT, TEXT) TO anon, authenticated;

-- 5. RPC Daftar atau Log Masuk Semula Ibu
DROP FUNCTION IF EXISTS public.register_or_login_mother(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.register_or_login_mother(
  p_mom_name TEXT,
  p_phone TEXT
)
RETURNS TABLE (
  ret_family_id UUID,
  ret_family_name TEXT,
  ret_invite_code TEXT,
  ret_is_existing BOOLEAN,
  ret_access_token TEXT
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

  SELECT * INTO v_family
  FROM public.families f
  WHERE position('[' || v_clean_phone || ']' in coalesce(f.family_name, '')) > 0
  LIMIT 1;

  IF FOUND THEN
    IF v_family.access_token IS NULL OR trim(v_family.access_token) = '' THEN
      UPDATE public.families f
      SET access_token = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
      WHERE f.id = v_family.id
      RETURNING * INTO v_family;
    END IF;

    RETURN QUERY SELECT
      v_family.id,
      split_part(coalesce(v_family.family_name, 'Keluarga'), ' [', 1),
      v_family.invite_code,
      true,
      v_family.access_token;
    RETURN;
  END IF;

  SELECT * INTO v_family
  FROM public.families f
  WHERE lower(trim(coalesce(f.family_name, ''))) = lower('Keluarga ' || v_mom_name)
    AND position('[' in coalesce(f.family_name, '')) = 0
  LIMIT 1;

  IF FOUND THEN
    UPDATE public.families f
    SET
      family_name = 'Keluarga ' || v_mom_name || ' [' || v_clean_phone || ']',
      access_token = coalesce(nullif(trim(f.access_token), ''), replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
    WHERE f.id = v_family.id
    RETURNING * INTO v_family;

    RETURN QUERY SELECT
      v_family.id,
      'Keluarga ' || v_mom_name,
      v_family.invite_code,
      true,
      v_family.access_token;
    RETURN;
  END IF;

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
        INSERT INTO public.families (family_name, invite_code, access_token)
        VALUES (
          'Keluarga ' || v_mom_name || ' [' || v_clean_phone || ']',
          v_new_code,
          replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
        )
        RETURNING * INTO v_family;

        RETURN QUERY SELECT
          v_family.id,
          'Keluarga ' || v_mom_name,
          v_family.invite_code,
          false,
          v_family.access_token;
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

-- 6. RPC Baca Rekod Kesihatan Keluarga (memerlukan family_id + access_token sah)
CREATE OR REPLACE FUNCTION public.family_get_records(
  p_family_id UUID,
  p_access_token TEXT,
  p_table TEXT,
  p_category TEXT DEFAULT NULL,
  p_exclude_category TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB := '[]'::jsonb;
BEGIN
  IF NOT public._verify_family_token(p_family_id, p_access_token, true) THEN
    RAISE EXCEPTION 'UNAUTHORIZED_FAMILY';
  END IF;

  IF p_table = 'children' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_result
    FROM (
      SELECT * FROM public.children c
      WHERE c.family_id = p_family_id
      ORDER BY c.created_at DESC
    ) t;
  ELSIF p_table = 'appointments' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_result
    FROM (
      SELECT * FROM public.appointments a
      WHERE a.family_id = p_family_id
      ORDER BY a.appointment_date ASC
    ) t;
  ELSIF p_table = 'health_vitals' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_result
    FROM (
      SELECT * FROM public.health_vitals v
      WHERE v.family_id = p_family_id
      ORDER BY v.logged_date DESC
    ) t;
  ELSIF p_table = 'allergies' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_result
    FROM (
      SELECT * FROM public.allergies al
      WHERE al.family_id = p_family_id
      ORDER BY al.created_at DESC
    ) t;
  ELSIF p_table = 'baby_memories' THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_result
    FROM (
      SELECT * FROM public.baby_memories m
      WHERE m.family_id = p_family_id
        AND (p_category IS NULL OR m.category = p_category)
        AND (p_exclude_category IS NULL OR m.category IS DISTINCT FROM p_exclude_category)
      ORDER BY m.memory_date DESC NULLS LAST, m.created_at DESC
    ) t;
  ELSE
    RAISE EXCEPTION 'INVALID_TABLE';
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.family_get_records(UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.family_get_records(UUID, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 7. RPC Tambah Rekod Kesihatan Keluarga (menolak Mod Demo & tanpa token sah)
CREATE OR REPLACE FUNCTION public.family_insert_record(
  p_family_id UUID,
  p_access_token TEXT,
  p_table TEXT,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean JSONB := '{}'::jsonb;
  v_child public.children%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
  v_vital public.health_vitals%ROWTYPE;
  v_allergy public.allergies%ROWTYPE;
  v_mem public.baby_memories%ROWTYPE;
BEGIN
  IF NOT public._verify_family_token(p_family_id, p_access_token, false) THEN
    RAISE EXCEPTION 'UNAUTHORIZED_FAMILY';
  END IF;

  IF p_table = 'children' THEN
    v_clean := jsonb_build_object(
      'family_id', p_family_id,
      'nickname', p_payload->>'nickname',
      'status', p_payload->>'status',
      'edd_date', nullif(trim(coalesce(p_payload->>'edd_date', '')), ''),
      'birth_date', nullif(trim(coalesce(p_payload->>'birth_date', '')), ''),
      'blood_type', coalesce(nullif(trim(coalesce(p_payload->>'blood_type', '')), ''), 'O+')
    );
    v_child := jsonb_populate_record(NULL::public.children, v_clean);
    INSERT INTO public.children (family_id, nickname, status, edd_date, birth_date, blood_type)
    VALUES (p_family_id, v_child.nickname, v_child.status, v_child.edd_date, v_child.birth_date, v_child.blood_type)
    RETURNING * INTO v_child;
    RETURN to_jsonb(v_child);

  ELSIF p_table = 'appointments' THEN
    v_clean := jsonb_build_object(
      'family_id', p_family_id,
      'title', p_payload->>'title',
      'clinic_name', p_payload->>'clinic_name',
      'appointment_date', nullif(trim(coalesce(p_payload->>'appointment_date', '')), ''),
      'appointment_time', nullif(trim(coalesce(p_payload->>'appointment_time', '')), ''),
      'notes', p_payload->>'notes',
      'category', p_payload->>'category'
    );
    v_appt := jsonb_populate_record(NULL::public.appointments, v_clean);
    INSERT INTO public.appointments (family_id, title, clinic_name, appointment_date, appointment_time, notes, category)
    VALUES (p_family_id, v_appt.title, v_appt.clinic_name, v_appt.appointment_date, v_appt.appointment_time, v_appt.notes, v_appt.category)
    RETURNING * INTO v_appt;
    RETURN to_jsonb(v_appt);

  ELSIF p_table = 'health_vitals' THEN
    v_clean := jsonb_build_object(
      'family_id', p_family_id,
      'hb_reading', p_payload->'hb_reading',
      'blood_pressure', p_payload->>'blood_pressure',
      'weight', p_payload->'weight',
      'gestation_week', p_payload->>'gestation_week',
      'logged_date', nullif(trim(coalesce(p_payload->>'logged_date', '')), '')
    );
    v_vital := jsonb_populate_record(NULL::public.health_vitals, v_clean);
    INSERT INTO public.health_vitals (family_id, hb_reading, blood_pressure, weight, gestation_week, logged_date)
    VALUES (p_family_id, v_vital.hb_reading, v_vital.blood_pressure, v_vital.weight, v_vital.gestation_week, v_vital.logged_date)
    RETURNING * INTO v_vital;
    RETURN to_jsonb(v_vital);

  ELSIF p_table = 'allergies' THEN
    v_clean := jsonb_build_object(
      'family_id', p_family_id,
      'item_name', p_payload->>'item_name',
      'category', p_payload->>'category',
      'symptoms', p_payload->>'symptoms',
      'recorded_by', p_payload->>'recorded_by'
    );
    v_allergy := jsonb_populate_record(NULL::public.allergies, v_clean);
    INSERT INTO public.allergies (family_id, item_name, category, symptoms, recorded_by)
    VALUES (p_family_id, v_allergy.item_name, v_allergy.category, v_allergy.symptoms, v_allergy.recorded_by)
    RETURNING * INTO v_allergy;
    RETURN to_jsonb(v_allergy);

  ELSIF p_table = 'baby_memories' THEN
    v_clean := jsonb_build_object(
      'family_id', p_family_id,
      'title', p_payload->>'title',
      'category', p_payload->>'category',
      'memory_date', nullif(trim(coalesce(p_payload->>'memory_date', '')), ''),
      'notes', p_payload->>'notes',
      'image_url', p_payload->>'image_url',
      'uploaded_by', p_payload->>'uploaded_by'
    );
    v_mem := jsonb_populate_record(NULL::public.baby_memories, v_clean);
    INSERT INTO public.baby_memories (family_id, title, category, memory_date, notes, image_url, uploaded_by)
    VALUES (p_family_id, v_mem.title, v_mem.category, v_mem.memory_date, v_mem.notes, v_mem.image_url, v_mem.uploaded_by)
    RETURNING * INTO v_mem;
    RETURN to_jsonb(v_mem);
  ELSE
    RAISE EXCEPTION 'INVALID_TABLE';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.family_insert_record(UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.family_insert_record(UUID, TEXT, TEXT, JSONB) TO anon, authenticated;

-- 8. RPC Kemaskini Rekod Kesihatan Keluarga (disahkan milik p_family_id sahaja)
CREATE OR REPLACE FUNCTION public.family_update_record(
  p_family_id UUID,
  p_access_token TEXT,
  p_table TEXT,
  p_row_id TEXT,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean JSONB := '{}'::jsonb;
  v_appt public.appointments%ROWTYPE;
  v_vital public.health_vitals%ROWTYPE;
  v_allergy public.allergies%ROWTYPE;
  v_mem public.baby_memories%ROWTYPE;
BEGIN
  IF NOT public._verify_family_token(p_family_id, p_access_token, false) THEN
    RAISE EXCEPTION 'UNAUTHORIZED_FAMILY';
  END IF;

  IF p_table = 'appointments' THEN
    SELECT * INTO v_appt FROM public.appointments WHERE id::text = p_row_id AND family_id = p_family_id LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_clean :=
      (CASE WHEN p_payload ? 'title' THEN jsonb_build_object('title', p_payload->>'title') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'clinic_name' THEN jsonb_build_object('clinic_name', p_payload->>'clinic_name') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'appointment_date' THEN jsonb_build_object('appointment_date', nullif(trim(coalesce(p_payload->>'appointment_date', '')), '')) ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'appointment_time' THEN jsonb_build_object('appointment_time', nullif(trim(coalesce(p_payload->>'appointment_time', '')), '')) ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'notes' THEN jsonb_build_object('notes', p_payload->>'notes') ELSE '{}'::jsonb END);
    v_appt := jsonb_populate_record(v_appt, v_clean);
    UPDATE public.appointments
    SET title = v_appt.title, clinic_name = v_appt.clinic_name, appointment_date = v_appt.appointment_date,
        appointment_time = v_appt.appointment_time, notes = v_appt.notes
    WHERE id = v_appt.id AND family_id = p_family_id
    RETURNING * INTO v_appt;
    RETURN to_jsonb(v_appt);

  ELSIF p_table = 'health_vitals' THEN
    SELECT * INTO v_vital FROM public.health_vitals WHERE id::text = p_row_id AND family_id = p_family_id LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_clean :=
      (CASE WHEN p_payload ? 'hb_reading' THEN jsonb_build_object('hb_reading', p_payload->'hb_reading') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'blood_pressure' THEN jsonb_build_object('blood_pressure', p_payload->>'blood_pressure') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'weight' THEN jsonb_build_object('weight', p_payload->'weight') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'logged_date' THEN jsonb_build_object('logged_date', nullif(trim(coalesce(p_payload->>'logged_date', '')), '')) ELSE '{}'::jsonb END);
    v_vital := jsonb_populate_record(v_vital, v_clean);
    UPDATE public.health_vitals
    SET hb_reading = v_vital.hb_reading, blood_pressure = v_vital.blood_pressure,
        weight = v_vital.weight, logged_date = v_vital.logged_date
    WHERE id = v_vital.id AND family_id = p_family_id
    RETURNING * INTO v_vital;
    RETURN to_jsonb(v_vital);

  ELSIF p_table = 'allergies' THEN
    SELECT * INTO v_allergy FROM public.allergies WHERE id::text = p_row_id AND family_id = p_family_id LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_clean :=
      (CASE WHEN p_payload ? 'item_name' THEN jsonb_build_object('item_name', p_payload->>'item_name') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'category' THEN jsonb_build_object('category', p_payload->>'category') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'symptoms' THEN jsonb_build_object('symptoms', p_payload->>'symptoms') ELSE '{}'::jsonb END);
    v_allergy := jsonb_populate_record(v_allergy, v_clean);
    UPDATE public.allergies
    SET item_name = v_allergy.item_name, category = v_allergy.category, symptoms = v_allergy.symptoms
    WHERE id = v_allergy.id AND family_id = p_family_id
    RETURNING * INTO v_allergy;
    RETURN to_jsonb(v_allergy);

  ELSIF p_table = 'baby_memories' THEN
    SELECT * INTO v_mem FROM public.baby_memories WHERE id::text = p_row_id AND family_id = p_family_id LIMIT 1;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_clean :=
      (CASE WHEN p_payload ? 'title' THEN jsonb_build_object('title', p_payload->>'title') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'category' THEN jsonb_build_object('category', p_payload->>'category') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'memory_date' THEN jsonb_build_object('memory_date', nullif(trim(coalesce(p_payload->>'memory_date', '')), '')) ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'notes' THEN jsonb_build_object('notes', p_payload->>'notes') ELSE '{}'::jsonb END) ||
      (CASE WHEN p_payload ? 'image_url' THEN jsonb_build_object('image_url', p_payload->'image_url') ELSE '{}'::jsonb END);
    v_mem := jsonb_populate_record(v_mem, v_clean);
    UPDATE public.baby_memories
    SET title = v_mem.title, category = v_mem.category, memory_date = v_mem.memory_date,
        notes = v_mem.notes, image_url = v_mem.image_url
    WHERE id = v_mem.id AND family_id = p_family_id
    RETURNING * INTO v_mem;
    RETURN to_jsonb(v_mem);
  ELSE
    RAISE EXCEPTION 'INVALID_TABLE';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.family_update_record(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.family_update_record(UUID, TEXT, TEXT, TEXT, JSONB) TO anon, authenticated;

-- 9. RPC Padam Rekod Kesihatan Keluarga (disahkan milik p_family_id sahaja)
CREATE OR REPLACE FUNCTION public.family_delete_record(
  p_family_id UUID,
  p_access_token TEXT,
  p_table TEXT,
  p_row_id TEXT DEFAULT NULL,
  p_category TEXT DEFAULT NULL,
  p_title_substr TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public._verify_family_token(p_family_id, p_access_token, false) THEN
    RAISE EXCEPTION 'UNAUTHORIZED_FAMILY';
  END IF;

  IF p_table NOT IN ('appointments', 'health_vitals', 'allergies', 'baby_memories') THEN
    RAISE EXCEPTION 'INVALID_TABLE';
  END IF;

  IF p_row_id IS NOT NULL AND trim(p_row_id) <> '' THEN
    EXECUTE format('DELETE FROM public.%I WHERE family_id = $1 AND id::text = $2', p_table)
    USING p_family_id, p_row_id;
    RETURN true;
  ELSIF p_table = 'baby_memories' AND p_category IS NOT NULL AND p_title_substr IS NOT NULL THEN
    DELETE FROM public.baby_memories
    WHERE family_id = p_family_id
      AND category = p_category
      AND position(p_title_substr in coalesce(title, '')) > 0;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.family_delete_record(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.family_delete_record(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
