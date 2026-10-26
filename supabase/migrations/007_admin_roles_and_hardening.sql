-- ============================================
-- 1. ROLES
-- ============================================
ALTER TABLE profiles
    ADD COLUMN role VARCHAR(10) NOT NULL DEFAULT 'user'
    CHECK (role IN ('user', 'admin'));

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles
        WHERE user_id = auth.uid() AND role = 'admin'
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- Requests from end users carry auth.uid(); cron, migrations and the parser (service_role) do not
CREATE OR REPLACE FUNCTION is_end_user_non_admin()
RETURNS BOOLEAN AS $$
    SELECT auth.uid() IS NOT NULL AND NOT is_admin();
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================
-- 2. PROTECT COMPUTED / PRIVILEGED COLUMNS
-- ============================================
-- RLS lets users update their own profile and authors update their publications,
-- but metrics and roles must only change through the system.

CREATE OR REPLACE FUNCTION protect_profile_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF is_end_user_non_admin() THEN
        NEW.role := OLD.role;
        NEW.user_id := OLD.user_id;
        NEW.h_index := OLD.h_index;
        NEW.i10_index := OLD.i10_index;
        NEW.h_index_updated_at := OLD.h_index_updated_at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trg_protect_profile_columns
BEFORE UPDATE ON profiles
FOR EACH ROW EXECUTE FUNCTION protect_profile_columns();

CREATE OR REPLACE FUNCTION protect_publication_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF is_end_user_non_admin() THEN
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

-- Who added the publication (NULL for seed / legacy rows)
ALTER TABLE publications
    ADD COLUMN created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE TRIGGER trg_protect_publication_columns
BEFORE INSERT OR UPDATE ON publications
FOR EACH ROW EXECUTE FUNCTION protect_publication_columns();

-- citation_count is maintained by this trigger; it must work regardless of the caller's RLS
CREATE OR REPLACE FUNCTION update_citation_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE publications
        SET citation_count = citation_count + 1
        WHERE id = NEW.target_publication_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE publications
        SET citation_count = greatest(citation_count - 1, 0)
        WHERE id = OLD.target_publication_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 3. RLS: owners + admin
-- ============================================

-- Is the current user allowed to manage this publication's authors / references?
CREATE OR REPLACE FUNCTION can_manage_publication(p_publication_id UUID)
RETURNS BOOLEAN AS $$
    SELECT is_admin()
        OR EXISTS (
            SELECT 1 FROM publications
            WHERE id = p_publication_id AND created_by = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM publication_authors pa
            JOIN profiles pr ON pr.id = pa.profile_id
            WHERE pa.publication_id = p_publication_id AND pr.user_id = auth.uid()
        );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- publications
DROP POLICY "publications_update" ON publications;
CREATE POLICY "publications_update" ON publications
    FOR UPDATE TO authenticated
    USING (can_manage_publication(id));

CREATE POLICY "publications_delete" ON publications
    FOR DELETE TO authenticated
    USING (is_admin() OR created_by = auth.uid());

-- publication_authors
DROP POLICY "pub_authors_insert" ON publication_authors;
CREATE POLICY "pub_authors_insert" ON publication_authors
    FOR INSERT TO authenticated
    WITH CHECK (can_manage_publication(publication_id));

DROP POLICY "pub_authors_delete" ON publication_authors;
CREATE POLICY "pub_authors_delete" ON publication_authors
    FOR DELETE TO authenticated
    USING (
        is_admin()
        OR EXISTS (
            SELECT 1 FROM profiles pr
            WHERE pr.id = publication_authors.profile_id AND pr.user_id = auth.uid()
        )
    );

CREATE POLICY "pub_authors_update" ON publication_authors
    FOR UPDATE TO authenticated
    USING (is_admin());

-- journals: admin only
DROP POLICY "journals_insert" ON journals;
CREATE POLICY "journals_insert" ON journals
    FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "journals_update" ON journals
    FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "journals_delete" ON journals
    FOR DELETE TO authenticated USING (is_admin());

-- profiles: admin can manage any profile
CREATE POLICY "profiles_admin_insert" ON profiles
    FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "profiles_admin_update" ON profiles
    FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "profiles_admin_delete" ON profiles
    FOR DELETE TO authenticated USING (is_admin() AND user_id IS NULL);

-- raw_references
DROP POLICY "raw_refs_insert" ON raw_references;
CREATE POLICY "raw_refs_insert" ON raw_references
    FOR INSERT TO authenticated
    WITH CHECK (can_manage_publication(source_publication_id));
CREATE POLICY "raw_refs_admin_update" ON raw_references
    FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "raw_refs_admin_delete" ON raw_references
    FOR DELETE TO authenticated USING (is_admin());

-- citations: admin only (normally created by matching)
CREATE POLICY "citations_admin_insert" ON citations
    FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "citations_admin_delete" ON citations
    FOR DELETE TO authenticated USING (is_admin());

-- storage: uploader or admin can delete PDFs
CREATE POLICY "papers_admin_delete" ON storage.objects
    FOR DELETE TO authenticated
    USING (bucket_id = 'papers' AND is_admin());

-- ============================================
-- 4. REFERENCE STATUS: 'rejected'
-- ============================================
-- Rejected by an admin: never re-queued by rematch_on_new_publication()
ALTER TABLE raw_references DROP CONSTRAINT raw_references_status_check;
ALTER TABLE raw_references ADD CONSTRAINT raw_references_status_check
    CHECK (status IN ('pending', 'matched', 'unmatched', 'rejected'));

CREATE INDEX idx_raw_refs_unmatched ON raw_references (created_at DESC) WHERE status = 'unmatched';

-- ============================================
-- 5. H-INDEX: also reset authors who lost citations
-- ============================================
CREATE OR REPLACE FUNCTION recalculate_h_index(p_profile_id UUID)
RETURNS void AS $$
DECLARE
    v_h_index INT := 0;
    v_i10_index INT := 0;
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

    UPDATE profiles
    SET h_index = v_h_index,
        i10_index = v_i10_index,
        h_index_updated_at = now()
    WHERE id = p_profile_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION recalculate_all_h_indexes()
RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    v_profile_id UUID;
BEGIN
    FOR v_profile_id IN
        SELECT DISTINCT pa.profile_id
        FROM publication_authors pa
        JOIN publications p ON p.id = pa.publication_id
        WHERE p.citation_count > 0
        UNION
        SELECT id FROM profiles WHERE h_index > 0 OR i10_index > 0
    LOOP
        PERFORM recalculate_h_index(v_profile_id);
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION recalculate_publication_authors(p_publication_id UUID)
RETURNS void AS $$
DECLARE
    v_profile_id UUID;
BEGIN
    FOR v_profile_id IN
        SELECT profile_id FROM publication_authors WHERE publication_id = p_publication_id
    LOOP
        PERFORM recalculate_h_index(v_profile_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 6. ADMIN RPC
-- ============================================
CREATE OR REPLACE FUNCTION assert_admin()
RETURNS void AS $$
BEGIN
    IF auth.uid() IS NOT NULL AND NOT is_admin() THEN
        RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
    END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Manual triggers: admin only (cron calls them without auth.uid())
CREATE OR REPLACE FUNCTION run_matching()
RETURNS json AS $$
DECLARE
    v_result RECORD;
BEGIN
    PERFORM assert_admin();
    SELECT * INTO v_result FROM match_raw_references();
    RETURN json_build_object(
        'matched', v_result.matched_count,
        'pending', v_result.total_pending
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION run_h_index_update()
RETURNS json AS $$
DECLARE
    v_count INT;
BEGIN
    PERFORM assert_admin();
    SELECT recalculate_all_h_indexes() INTO v_count;
    RETURN json_build_object('profiles_updated', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION admin_stats()
RETURNS json AS $$
BEGIN
    PERFORM assert_admin();
    RETURN json_build_object(
        'publications', (SELECT count(*) FROM publications),
        'profiles', (SELECT count(*) FROM profiles),
        'registered_users', (SELECT count(*) FROM profiles WHERE user_id IS NOT NULL),
        'journals', (SELECT count(*) FROM journals),
        'citations', (SELECT count(*) FROM citations),
        'refs_pending', (SELECT count(*) FROM raw_references WHERE status = 'pending'),
        'refs_matched', (SELECT count(*) FROM raw_references WHERE status = 'matched'),
        'refs_unmatched', (SELECT count(*) FROM raw_references WHERE status = 'unmatched'),
        'refs_rejected', (SELECT count(*) FROM raw_references WHERE status = 'rejected'),
        'claims_pending', (SELECT count(*) FROM profile_claims WHERE status = 'pending'),
        'last_matching', (
            SELECT max(end_time) FROM cron.job_run_details d
            JOIN cron.job j ON j.jobid = d.jobid WHERE j.jobname = 'tsi-matching'
        ),
        'last_h_index', (SELECT max(h_index_updated_at) FROM profiles)
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, cron;

-- Candidate publications for an unresolved reference (looser than automatic matching)
CREATE OR REPLACE FUNCTION reference_candidates(p_ref_id UUID, p_limit INT DEFAULT 5)
RETURNS TABLE(id UUID, title TEXT, published_date DATE, score REAL) AS $$
BEGIN
    PERFORM assert_admin();
    RETURN QUERY
    SELECT p.id, p.title, p.published_date,
           greatest(similarity(r.parsed_title, p.title),
                    coalesce(similarity(r.parsed_title, p.title_en), 0),
                    similarity(r.raw_text, p.title)) AS score
    FROM raw_references r
    JOIN publications p ON p.id != r.source_publication_id
    WHERE r.id = p_ref_id
      AND (similarity(coalesce(r.parsed_title, ''), p.title) >= 0.15
           OR similarity(r.raw_text, p.title) >= 0.15)
    ORDER BY score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

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
        match_score = 1.0, matched_at = now()
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

-- Remove a citation when no matched reference supports it any more
CREATE OR REPLACE FUNCTION drop_orphan_citation(p_source UUID, p_target UUID)
RETURNS void AS $$
BEGIN
    DELETE FROM citations c
    WHERE c.source_publication_id = p_source
      AND c.target_publication_id = p_target
      AND NOT EXISTS (
          SELECT 1 FROM raw_references r
          WHERE r.source_publication_id = p_source
            AND r.matched_publication_id = p_target
            AND r.status = 'matched'
      );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- p_status: 'unmatched' (undo a wrong match) or 'rejected' (not in our database, stop retrying)
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
    SET status = p_status, matched_publication_id = NULL, match_score = NULL, matched_at = now()
    WHERE id = p_ref_id;

    IF v_target IS NOT NULL THEN
        PERFORM drop_orphan_citation(v_source, v_target);
        PERFORM recalculate_publication_authors(v_target);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Merge a duplicate / unclaimed author profile into another one
CREATE OR REPLACE FUNCTION merge_profiles(p_source UUID, p_target UUID)
RETURNS void AS $$
DECLARE
    v_src profiles%ROWTYPE;
BEGIN
    PERFORM assert_admin();
    IF p_source = p_target THEN
        RAISE EXCEPTION 'cannot merge a profile into itself';
    END IF;

    SELECT * INTO v_src FROM profiles WHERE id = p_source;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'source profile not found';
    END IF;
    IF v_src.user_id IS NOT NULL THEN
        RAISE EXCEPTION 'source profile belongs to a registered user';
    END IF;

    -- Move authorships the target does not already have
    UPDATE publication_authors pa
    SET profile_id = p_target
    WHERE pa.profile_id = p_source
      AND NOT EXISTS (
          SELECT 1 FROM publication_authors t
          WHERE t.publication_id = pa.publication_id AND t.profile_id = p_target
      );

    -- Other users' pending claims on this profile become moot
    UPDATE profile_claims SET status = 'merged', resolved_at = now()
    WHERE profile_id = p_source AND status = 'pending';

    -- Delete first: orcid is UNIQUE and may move to the target
    DELETE FROM profiles WHERE id = p_source;

    UPDATE profiles t
    SET full_name_en = coalesce(t.full_name_en, v_src.full_name_en,
                                CASE WHEN v_src.full_name != t.full_name THEN v_src.full_name END),
        institution = coalesce(t.institution, v_src.institution),
        orcid = coalesce(t.orcid, v_src.orcid)
    WHERE t.id = p_target;

    PERFORM recalculate_h_index(p_target);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 7. PROFILE CLAIMS ("this is me")
-- ============================================
-- A registered user asks to take over an unclaimed author profile created from PDFs.
CREATE TABLE profile_claims (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- SET NULL: an approved claim outlives the merged-away profile as history
    profile_id  UUID REFERENCES profiles(id) ON DELETE SET NULL,
    profile_name TEXT NOT NULL,
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status      VARCHAR(10) NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'rejected', 'merged')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX idx_profile_claims_one_pending
    ON profile_claims (profile_id, user_id) WHERE status = 'pending';

ALTER TABLE profile_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "claims_select" ON profile_claims
    FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "claims_insert" ON profile_claims
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND status = 'pending'
        AND EXISTS (
            SELECT 1 FROM profiles pr
            WHERE pr.id = profile_claims.profile_id AND pr.user_id IS NULL
        )
    );

CREATE OR REPLACE FUNCTION admin_resolve_claim(p_claim_id UUID, p_approve BOOLEAN)
RETURNS void AS $$
DECLARE
    v_claim profile_claims%ROWTYPE;
    v_user_profile UUID;
BEGIN
    PERFORM assert_admin();

    SELECT * INTO v_claim FROM profile_claims WHERE id = p_claim_id AND status = 'pending';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'claim not found or already resolved';
    END IF;

    IF p_approve THEN
        SELECT id INTO v_user_profile FROM profiles WHERE user_id = v_claim.user_id;
        IF v_user_profile IS NULL THEN
            RAISE EXCEPTION 'claimant has no profile';
        END IF;
        UPDATE profile_claims SET status = 'approved', resolved_at = now() WHERE id = p_claim_id;
        PERFORM merge_profiles(v_claim.profile_id, v_user_profile);
    ELSE
        UPDATE profile_claims SET status = 'rejected', resolved_at = now() WHERE id = p_claim_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- 8. SEARCH: total count for pagination, match by author name
-- ============================================
DROP FUNCTION search_publications(TEXT, UUID, INT, INT, VARCHAR, INT, INT);

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
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

DROP FUNCTION search_authors(TEXT, INT, INT);

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
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Public counters for the landing page
CREATE OR REPLACE FUNCTION public_stats()
RETURNS json AS $$
    SELECT json_build_object(
        'publications', (SELECT count(*) FROM publications),
        'authors', (SELECT count(*) FROM profiles),
        'journals', (SELECT count(*) FROM journals),
        'citations', (SELECT count(*) FROM citations)
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

-- ============================================
-- 9. GRANTS
-- ============================================
REVOKE EXECUTE ON FUNCTION run_matching() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION run_h_index_update() FROM PUBLIC, anon;

DO $$
DECLARE
    f TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'admin_stats()',
        'reference_candidates(uuid, int)',
        'admin_link_reference(uuid, uuid)',
        'admin_set_reference_status(uuid, text)',
        'merge_profiles(uuid, uuid)',
        'admin_resolve_claim(uuid, boolean)'
    ] LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
    END LOOP;

    -- Internal helpers: not callable through the API
    FOREACH f IN ARRAY ARRAY[
        'drop_orphan_citation(uuid, uuid)',
        'recalculate_publication_authors(uuid)',
        'recalculate_h_index(uuid)',
        'recalculate_all_h_indexes()',
        'match_raw_references(real, int)'
    ] LOOP
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public_stats() TO anon, authenticated;
