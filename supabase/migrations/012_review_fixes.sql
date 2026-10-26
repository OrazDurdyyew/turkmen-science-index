-- Fixes from the security / correctness review.

-- ============================================
-- 1. Trusted system writes bypass column protection
-- ============================================
-- protect_*_columns() froze citation_count / h_index for any request carrying a user's auth.uid(),
-- including writes made by the system on that user's behalf (citation_count decrement when the user
-- deletes their publication, h-index recalculation inside set_publication_authors). That let a user
-- inflate a citation count permanently. System code now marks its writes with a transaction-local flag.
CREATE OR REPLACE FUNCTION is_trusted_write()
RETURNS BOOLEAN AS $$
    SELECT coalesce(current_setting('tsi.trusted_write', true), '') = 'on';
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION protect_profile_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF is_end_user_non_admin() AND NOT is_trusted_write() THEN
        NEW.role := OLD.role;
        NEW.user_id := OLD.user_id;
        NEW.h_index := OLD.h_index;
        NEW.i10_index := OLD.i10_index;
        NEW.h_index_updated_at := OLD.h_index_updated_at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION protect_publication_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF is_end_user_non_admin() AND NOT is_trusted_write() THEN
        IF TG_OP = 'INSERT' THEN
            NEW.citation_count := 0;
            NEW.created_by := auth.uid();
        ELSE
            NEW.citation_count := OLD.citation_count;
            NEW.created_by := OLD.created_by;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION update_citation_count()
RETURNS TRIGGER AS $$
DECLARE
    v_prev TEXT := coalesce(current_setting('tsi.trusted_write', true), '');
BEGIN
    PERFORM set_config('tsi.trusted_write', 'on', true);
    IF TG_OP = 'INSERT' THEN
        UPDATE publications SET citation_count = citation_count + 1
        WHERE id = NEW.target_publication_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE publications SET citation_count = greatest(citation_count - 1, 0)
        WHERE id = OLD.target_publication_id;
    END IF;
    PERFORM set_config('tsi.trusted_write', v_prev, true);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION recalculate_h_index(p_profile_id UUID)
RETURNS void AS $$
DECLARE
    v_h_index INT := 0;
    v_i10_index INT := 0;
    v_prev TEXT := coalesce(current_setting('tsi.trusted_write', true), '');
BEGIN
    SELECT coalesce(max(rank), 0) INTO v_h_index
    FROM (
        SELECT citation_count,
               ROW_NUMBER() OVER (ORDER BY citation_count DESC) as rank
        FROM publications p
        JOIN publication_authors pa ON pa.publication_id = p.id
        WHERE pa.profile_id = p_profile_id
          AND p.citation_count > 0
    ) ranked
    WHERE citation_count >= rank;

    SELECT count(*) INTO v_i10_index
    FROM publications p
    JOIN publication_authors pa ON pa.publication_id = p.id
    WHERE pa.profile_id = p_profile_id
      AND p.citation_count >= 10;

    PERFORM set_config('tsi.trusted_write', 'on', true);
    UPDATE profiles
    SET h_index = v_h_index,
        i10_index = v_i10_index,
        h_index_updated_at = now()
    WHERE id = p_profile_id;
    PERFORM set_config('tsi.trusted_write', v_prev, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Safety net: citation_count is derived data; the hourly job re-derives it from citations
CREATE OR REPLACE FUNCTION reconcile_citation_counts()
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    PERFORM set_config('tsi.trusted_write', 'on', true);
    UPDATE publications p
    SET citation_count = c.n
    FROM (
        SELECT p2.id, count(ci.id)::int AS n
        FROM publications p2
        LEFT JOIN citations ci ON ci.target_publication_id = p2.id
        GROUP BY p2.id
    ) c
    WHERE c.id = p.id AND p.citation_count IS DISTINCT FROM c.n;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    PERFORM set_config('tsi.trusted_write', '', true);
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION run_h_index_update()
RETURNS json AS $$
DECLARE
    v_fixed INT;
    v_count INT;
BEGIN
    PERFORM assert_admin();
    SELECT reconcile_citation_counts() INTO v_fixed;
    SELECT recalculate_all_h_indexes() INTO v_count;
    RETURN json_build_object('profiles_updated', v_count, 'citation_counts_fixed', v_fixed);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Profiles touched by a reconcile must be recalculated too: include every author of a publication
-- whose count changed. Simplest correct option at MVP scale: recalc everyone with publications.
CREATE OR REPLACE FUNCTION recalculate_all_h_indexes()
RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    v_profile_id UUID;
BEGIN
    FOR v_profile_id IN
        SELECT DISTINCT pa.profile_id FROM publication_authors pa
        UNION
        SELECT id FROM profiles WHERE h_index > 0 OR i10_index > 0
    LOOP
        PERFORM recalculate_h_index(v_profile_id);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 2. Automatic author resolution never picks a registered profile
-- ============================================
-- Otherwise anyone could rename themselves to a known scientist and collect that person's papers.
-- Registered users get linked only as the uploader of their own PDF, by an admin, or via a claim.
CREATE OR REPLACE FUNCTION resolve_author_profile(
    p_full_name TEXT,
    p_full_name_en TEXT DEFAULT NULL,
    p_institution TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
    v_name TEXT := left(nullif(regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g'), ''), 200);
    v_name_en TEXT := left(nullif(regexp_replace(trim(coalesce(p_full_name_en, '')), '\s+', ' ', 'g'), ''), 200);
    v_inst TEXT := left(nullif(trim(p_institution), ''), 300);
BEGIN
    IF v_name IS NULL THEN
        v_name := v_name_en;
        v_name_en := NULL;
    END IF;
    IF v_name IS NULL THEN
        RETURN NULL;
    END IF;

    IF v_name ~ '[А-Яа-яЁё]' THEN
        SELECT id INTO v_id FROM profiles
        WHERE user_id IS NULL AND lower(full_name) = lower(v_name)
        ORDER BY created_at LIMIT 1;
    ELSE
        SELECT id INTO v_id FROM profiles
        WHERE user_id IS NULL
          AND (lower(full_name) = lower(v_name) OR lower(full_name_en) = lower(v_name))
        ORDER BY created_at LIMIT 1;
    END IF;

    IF v_id IS NOT NULL THEN
        -- Only unclaimed profiles are touched here; registered users edit their own data
        UPDATE profiles
        SET full_name_en = coalesce(full_name_en, v_name_en),
            institution = coalesce(institution, v_inst)
        WHERE id = v_id;
        RETURN v_id;
    END IF;

    INSERT INTO profiles (full_name, full_name_en, institution)
    VALUES (v_name, v_name_en, v_inst)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION resolve_author_profile(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION resolve_author_profile(TEXT, TEXT, TEXT) TO service_role;

-- ============================================
-- 3. Users can only queue references, not pre-match them
-- ============================================
DROP POLICY "raw_refs_insert" ON raw_references;
CREATE POLICY "raw_refs_insert" ON raw_references
    FOR INSERT TO authenticated
    WITH CHECK (
        can_manage_publication(source_publication_id)
        AND status = 'pending'
        AND matched_publication_id IS NULL
        AND match_score IS NULL
    );

-- ============================================
-- 4. "Unmatched" undo sticks: remember targets an admin rejected for this reference
-- ============================================
ALTER TABLE raw_references
    ADD COLUMN excluded_publication_ids UUID[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION admin_set_reference_status(p_ref_id UUID, p_status TEXT)
RETURNS void AS $$
DECLARE
    v_source UUID;
    v_target UUID;
BEGIN
    PERFORM assert_admin();
    IF p_status NOT IN ('unmatched', 'rejected', 'pending') THEN
        RAISE EXCEPTION 'invalid status %', p_status;
    END IF;

    SELECT source_publication_id, matched_publication_id INTO v_source, v_target
    FROM raw_references WHERE id = p_ref_id;

    UPDATE raw_references
    SET status = p_status,
        matched_publication_id = NULL,
        match_score = NULL,
        matched_at = now(),
        excluded_publication_ids = CASE
            WHEN v_target IS NOT NULL AND NOT v_target = ANY(excluded_publication_ids)
            THEN excluded_publication_ids || v_target
            ELSE excluded_publication_ids
        END
    WHERE id = p_ref_id;

    IF v_target IS NOT NULL THEN
        PERFORM drop_orphan_citation(v_source, v_target);
        PERFORM recalculate_publication_authors(v_target);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- An explicit manual link overrides an earlier exclusion
CREATE OR REPLACE FUNCTION admin_link_reference(p_ref_id UUID, p_publication_id UUID)
RETURNS void AS $$
DECLARE
    v_source UUID;
    v_old_target UUID;
BEGIN
    PERFORM assert_admin();

    SELECT source_publication_id, matched_publication_id INTO v_source, v_old_target
    FROM raw_references WHERE id = p_ref_id;
    IF v_source IS NULL THEN
        RAISE EXCEPTION 'reference not found';
    END IF;
    IF v_source = p_publication_id THEN
        RAISE EXCEPTION 'publication cannot cite itself';
    END IF;

    UPDATE raw_references
    SET status = 'matched', matched_publication_id = p_publication_id,
        match_score = 1.0, matched_at = now(),
        excluded_publication_ids = array_remove(excluded_publication_ids, p_publication_id)
    WHERE id = p_ref_id;

    INSERT INTO citations (source_publication_id, target_publication_id)
    VALUES (v_source, p_publication_id)
    ON CONFLICT DO NOTHING;

    IF v_old_target IS NOT NULL AND v_old_target != p_publication_id THEN
        PERFORM drop_orphan_citation(v_source, v_old_target);
        PERFORM recalculate_publication_authors(v_old_target);
    END IF;

    PERFORM recalculate_publication_authors(p_publication_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

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
        SELECT id, parsed_title, parsed_authors, parsed_year, source_publication_id, excluded_publication_ids
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
          AND NOT p.id = ANY(v_ref.excluded_publication_ids)
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

            IF FOUND THEN
                PERFORM recalculate_publication_authors(v_best_match.pub_id);
            END IF;

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

-- ============================================
-- 5. Deleting a cited publication returns its references to the matching pool
-- ============================================
CREATE OR REPLACE FUNCTION release_references_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE raw_references
    SET status = 'unmatched', matched_publication_id = NULL, match_score = NULL, matched_at = now()
    WHERE matched_publication_id = OLD.id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trg_release_references_on_delete
BEFORE DELETE ON publications
FOR EACH ROW EXECUTE FUNCTION release_references_on_delete();

UPDATE raw_references SET status = 'unmatched', matched_at = now()
WHERE status = 'matched' AND matched_publication_id IS NULL;

-- ============================================
-- 6. Storage: no direct uploads (the parser uploads with the service key);
--    the publication's creator may delete its PDF before deleting the publication
-- ============================================
DROP POLICY IF EXISTS "papers_upload" ON storage.objects;

CREATE POLICY "papers_owner_delete" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'papers'
        AND EXISTS (
            SELECT 1 FROM public.publications p
            WHERE p.pdf_path = storage.objects.name AND p.created_by = auth.uid()
        )
    );

-- ============================================
-- 7. Cap page sizes of public search RPCs
-- ============================================

CREATE OR REPLACE FUNCTION clamp_limit(p_limit INT, p_max INT DEFAULT 100)
RETURNS INT AS $$
    SELECT least(greatest(coalesce(p_limit, 20), 1), p_max);
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION search_publications(
    p_query TEXT,
    p_journal_id UUID DEFAULT NULL,
    p_year_from INT DEFAULT NULL,
    p_year_to INT DEFAULT NULL,
    p_language VARCHAR DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0,
    p_sort TEXT DEFAULT 'relevance'
)
RETURNS TABLE(
    id UUID,
    title TEXT,
    abstract TEXT,
    published_date DATE,
    citation_count INT,
    language VARCHAR,
    journal_title TEXT,
    authors TEXT,
    rank REAL,
    total_count BIGINT
) AS $$
DECLARE
    v_q TEXT := nullif(trim(p_query), '');
BEGIN
    RETURN QUERY
    WITH matched AS (
        SELECT
            p.*,
            CASE
                WHEN v_q IS NOT NULL THEN
                    GREATEST(
                        ts_rank(
                            to_tsvector('russian', coalesce(p.title, '') || ' ' || coalesce(p.abstract, '')),
                            plainto_tsquery('russian', v_q)
                        ),
                        similarity(p.title, v_q),
                        coalesce((
                            SELECT max(greatest(similarity(pr.full_name, v_q),
                                                coalesce(similarity(pr.full_name_en, v_q), 0)))
                            FROM publication_authors pa
                            JOIN profiles pr ON pr.id = pa.profile_id
                            WHERE pa.publication_id = p.id
                        ), 0)
                    )
                ELSE 1.0
            END::REAL AS rnk
        FROM publications p
        WHERE
            (
                v_q IS NULL
                OR to_tsvector('russian', coalesce(p.title, '') || ' ' || coalesce(p.abstract, ''))
                    @@ plainto_tsquery('russian', v_q)
                OR similarity(p.title, v_q) >= 0.2
                OR EXISTS (
                    SELECT 1 FROM publication_authors pa
                    JOIN profiles pr ON pr.id = pa.profile_id
                    WHERE pa.publication_id = p.id
                      AND (similarity(pr.full_name, v_q) >= 0.3
                           OR similarity(pr.full_name_en, v_q) >= 0.3)
                )
            )
            AND (p_journal_id IS NULL OR p.journal_id = p_journal_id)
            AND (p_year_from IS NULL OR extract(year FROM p.published_date) >= p_year_from)
            AND (p_year_to IS NULL OR extract(year FROM p.published_date) <= p_year_to)
            AND (p_language IS NULL OR p.language = p_language)
    )
    SELECT
        m.id, m.title, m.abstract, m.published_date, m.citation_count, m.language,
        j.title AS journal_title,
        (
            SELECT string_agg(pr.full_name, ', ' ORDER BY pa.position)
            FROM publication_authors pa
            JOIN profiles pr ON pr.id = pa.profile_id
            WHERE pa.publication_id = m.id
        ) AS authors,
        m.rnk AS rank,
        count(*) OVER () AS total_count
    FROM matched m
    LEFT JOIN journals j ON j.id = m.journal_id
    ORDER BY
        CASE WHEN p_sort = 'citations' THEN m.citation_count END DESC NULLS LAST,
        CASE WHEN p_sort = 'date' THEN m.published_date END DESC NULLS LAST,
        m.rnk DESC,
        m.citation_count DESC
    LIMIT clamp_limit(p_limit)
    OFFSET least(greatest(coalesce(p_offset, 0), 0), 100000);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION search_authors(
    p_query TEXT,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE(
    id UUID,
    full_name TEXT,
    full_name_en TEXT,
    institution TEXT,
    h_index INT,
    i10_index INT,
    publication_count BIGINT,
    is_registered BOOLEAN,
    rank REAL,
    total_count BIGINT
) AS $$
DECLARE
    v_q TEXT := nullif(trim(p_query), '');
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.full_name,
        pr.full_name_en,
        pr.institution,
        pr.h_index,
        pr.i10_index,
        (SELECT count(*) FROM publication_authors pa WHERE pa.profile_id = pr.id) AS publication_count,
        pr.user_id IS NOT NULL AS is_registered,
        CASE
            WHEN v_q IS NOT NULL
            THEN greatest(similarity(pr.full_name, v_q),
                          coalesce(similarity(pr.full_name_en, v_q), 0))
            ELSE 1.0
        END::REAL AS rank,
        count(*) OVER () AS total_count
    FROM profiles pr
    WHERE
        v_q IS NULL
        OR similarity(pr.full_name, v_q) >= 0.15
        OR similarity(pr.full_name_en, v_q) >= 0.15
        OR pr.full_name ILIKE '%' || v_q || '%'
        OR pr.full_name_en ILIKE '%' || v_q || '%'
    ORDER BY rank DESC, pr.h_index DESC, pr.full_name
    LIMIT clamp_limit(p_limit)
    OFFSET least(greatest(coalesce(p_offset, 0), 0), 100000);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION autocomplete(
    p_query TEXT,
    p_limit INT DEFAULT 5
)
RETURNS TABLE(
    type TEXT,
    id UUID,
    label TEXT,
    sublabel TEXT
) AS $$
BEGIN
    -- Publications
    RETURN QUERY
    SELECT
        'publication'::TEXT AS type,
        p.id,
        p.title AS label,
        extract(year FROM p.published_date)::TEXT AS sublabel
    FROM publications p
    WHERE p.title ILIKE '%' || p_query || '%'
    ORDER BY p.citation_count DESC
    LIMIT clamp_limit(p_limit);

    -- Authors
    RETURN QUERY
    SELECT
        'author'::TEXT AS type,
        pr.id,
        pr.full_name AS label,
        pr.institution AS sublabel
    FROM profiles pr
    WHERE pr.full_name ILIKE '%' || p_query || '%'
    ORDER BY pr.h_index DESC
    LIMIT clamp_limit(p_limit);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;
