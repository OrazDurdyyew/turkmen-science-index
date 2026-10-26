-- resolve_author_profile matched the incoming English name against full_name_en.
-- English names from PDFs carry no patronymic ("Sokolov Artem"), so two different people
-- (Соколов Артем Игоревич / Соколов Артем Дмитриевич) were merged into one profile.
-- Now: a Cyrillic full name is matched only against full_name; English names are used for
-- matching only when no native-script name is available.
CREATE OR REPLACE FUNCTION resolve_author_profile(
    p_full_name TEXT,
    p_full_name_en TEXT DEFAULT NULL,
    p_institution TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_name TEXT := nullif(regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g'), '');
    v_name_en TEXT := nullif(regexp_replace(trim(coalesce(p_full_name_en, '')), '\s+', ' ', 'g'), '');
BEGIN
    IF v_name IS NULL THEN
        v_name := v_name_en;
        v_name_en := NULL;
    END IF;
    IF v_name IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_name ~ '[А-Яа-яЁё]' THEN
        SELECT id INTO v_id
        FROM profiles
        WHERE lower(full_name) = lower(v_name)
        ORDER BY (user_id IS NOT NULL) DESC, created_at
        LIMIT 1;
    ELSE
        SELECT id INTO v_id
        FROM profiles
        WHERE lower(full_name) = lower(v_name)
           OR lower(full_name_en) = lower(v_name)
        ORDER BY (user_id IS NOT NULL) DESC, created_at
        LIMIT 1;
    END IF;

    IF v_id IS NOT NULL THEN
        UPDATE profiles
        SET full_name_en = coalesce(full_name_en, v_name_en),
            institution = coalesce(institution, nullif(trim(p_institution), ''))
        WHERE id = v_id;
        RETURN v_id;
    END IF;

    INSERT INTO profiles (full_name, full_name_en, institution)
    VALUES (v_name, v_name_en, nullif(trim(p_institution), ''))
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION resolve_author_profile(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION resolve_author_profile(TEXT, TEXT, TEXT) TO service_role;
