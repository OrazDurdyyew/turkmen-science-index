-- ============================================
-- 1. PROFILES WITHOUT ACCOUNT
-- ============================================
-- Authors extracted from PDFs get a profile even if they never registered.
-- user_id IS NULL  → unclaimed author profile
-- user_id NOT NULL → registered user (profile.id = user_id for them)

ALTER TABLE profiles
    ADD COLUMN user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;

UPDATE profiles SET user_id = id;

ALTER TABLE profiles DROP CONSTRAINT profiles_id_fkey;
ALTER TABLE profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();

CREATE INDEX idx_profiles_full_name_lower ON profiles (lower(full_name));
CREATE INDEX idx_profiles_full_name_en_lower ON profiles (lower(full_name_en))
    WHERE full_name_en IS NOT NULL;

-- Registered users keep profile.id = auth.uid(), so existing frontend code keeps working
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, user_id, full_name)
    VALUES (NEW.id, NEW.id, coalesce(NEW.raw_user_meta_data->>'full_name', ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- RLS: ownership is now user_id, not id
DROP POLICY "profiles_update" ON profiles;
CREATE POLICY "profiles_update" ON profiles
    FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY "publications_update" ON publications;
CREATE POLICY "publications_update" ON publications
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM publication_authors pa
            JOIN profiles pr ON pr.id = pa.profile_id
            WHERE pa.publication_id = publications.id
              AND pr.user_id = auth.uid()
        )
    );

DROP POLICY "pub_authors_delete" ON publication_authors;
CREATE POLICY "pub_authors_delete" ON publication_authors
    FOR DELETE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM profiles pr
            WHERE pr.id = publication_authors.profile_id
              AND pr.user_id = auth.uid()
        )
    );

-- Find an author profile by exact name (case-insensitive) or create an unclaimed one.
-- Exact match only: fuzzy matching would merge different people with similar names.
CREATE OR REPLACE FUNCTION resolve_author_profile(
    p_full_name TEXT,
    p_full_name_en TEXT DEFAULT NULL,
    p_institution TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_name TEXT := nullif(trim(p_full_name), '');
    v_name_en TEXT := nullif(trim(p_full_name_en), '');
BEGIN
    IF v_name IS NULL THEN
        v_name := v_name_en;
        v_name_en := NULL;
    END IF;
    IF v_name IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT id INTO v_id
    FROM profiles
    WHERE lower(full_name) = lower(v_name)
       OR lower(full_name_en) = lower(v_name)
       OR (v_name_en IS NOT NULL AND lower(full_name_en) = lower(v_name_en))
    ORDER BY (user_id IS NOT NULL) DESC, created_at
    LIMIT 1;

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

-- Author search also looks at the English name
CREATE OR REPLACE FUNCTION search_authors(
    p_query TEXT,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE(
    id UUID,
    full_name TEXT,
    institution TEXT,
    h_index INT,
    i10_index INT,
    publication_count BIGINT,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.full_name,
        pr.institution,
        pr.h_index,
        pr.i10_index,
        (SELECT count(*) FROM publication_authors pa WHERE pa.profile_id = pr.id) AS publication_count,
        CASE
            WHEN p_query IS NOT NULL AND length(p_query) > 0
            THEN greatest(similarity(pr.full_name, p_query),
                          coalesce(similarity(pr.full_name_en, p_query), 0))
            ELSE 1.0
        END AS rank
    FROM profiles pr
    WHERE
        p_query IS NULL
        OR length(p_query) = 0
        OR similarity(pr.full_name, p_query) >= 0.15
        OR similarity(pr.full_name_en, p_query) >= 0.15
    ORDER BY rank DESC, pr.h_index DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================
-- 2. MATCHING: stricter threshold + year check
-- ============================================
-- 0.3 produced false positives (unrelated titles sharing "record linkage" scored 0.31–0.35).
-- A candidate whose year differs by more than 1 from the reference is rejected.

CREATE OR REPLACE FUNCTION match_raw_references(
    p_threshold REAL DEFAULT 0.6,
    p_batch_size INT DEFAULT 500
)
RETURNS TABLE(matched_count INT, total_pending INT) AS $$
DECLARE
    v_matched INT := 0;
    v_total INT;
    v_ref RECORD;
    v_best_match RECORD;
    v_final_score REAL;
BEGIN
    SELECT count(*) INTO v_total
    FROM raw_references WHERE status = 'pending';

    FOR v_ref IN
        SELECT id, parsed_title, parsed_authors, parsed_year, source_publication_id
        FROM raw_references
        WHERE status = 'pending'
        LIMIT p_batch_size
    LOOP
        IF v_ref.parsed_title IS NULL OR length(v_ref.parsed_title) < 5 THEN
            UPDATE raw_references
            SET status = 'unmatched', matched_at = now()
            WHERE id = v_ref.id;
            CONTINUE;
        END IF;

        SELECT
            p.id AS pub_id,
            extract(year FROM p.published_date)::int AS pub_year,
            greatest(similarity(v_ref.parsed_title, p.title),
                     coalesce(similarity(v_ref.parsed_title, p.title_en), 0)) AS title_sim
        INTO v_best_match
        FROM publications p
        WHERE p.id != v_ref.source_publication_id
          AND greatest(similarity(v_ref.parsed_title, p.title),
                       coalesce(similarity(v_ref.parsed_title, p.title_en), 0)) >= p_threshold
          AND (
              v_ref.parsed_year IS NULL
              OR p.published_date IS NULL
              OR abs(v_ref.parsed_year - extract(year FROM p.published_date)::int) <= 1
          )
        ORDER BY title_sim DESC
        LIMIT 1;

        IF v_best_match.pub_id IS NOT NULL THEN
            v_final_score := v_best_match.title_sim;
            IF v_ref.parsed_year IS NOT NULL AND v_ref.parsed_year = v_best_match.pub_year THEN
                v_final_score := least(v_final_score + 0.1, 1.0);
            END IF;

            UPDATE raw_references
            SET matched_publication_id = v_best_match.pub_id,
                match_score = v_final_score,
                status = 'matched',
                matched_at = now()
            WHERE id = v_ref.id;

            INSERT INTO citations (source_publication_id, target_publication_id)
            VALUES (v_ref.source_publication_id, v_best_match.pub_id)
            ON CONFLICT DO NOTHING;

            v_matched := v_matched + 1;
        ELSE
            UPDATE raw_references
            SET status = 'unmatched', matched_at = now()
            WHERE id = v_ref.id;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_matched, v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION rematch_on_new_publication()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE raw_references
    SET status = 'pending'
    WHERE status = 'unmatched'
      AND parsed_title IS NOT NULL
      AND greatest(similarity(parsed_title, NEW.title),
                   coalesce(similarity(parsed_title, NEW.title_en), 0)) >= 0.6;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION run_matching()
RETURNS json AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT * INTO v_result FROM match_raw_references();
    RETURN json_build_object(
        'matched', v_result.matched_count,
        'pending', v_result.total_pending
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 3. SCHEDULE via pg_cron
-- ============================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule('tsi-matching', '*/10 * * * *', 'SELECT public.run_matching()');
SELECT cron.schedule('tsi-h-index', '0 * * * *', 'SELECT public.run_h_index_update()');
