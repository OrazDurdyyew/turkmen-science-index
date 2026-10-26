-- Signed-in users adding a publication by hand need to reference co-authors who are not
-- registered. This wraps resolve_author_profile (service-only) with an auth check and limits.
CREATE OR REPLACE FUNCTION find_or_create_author(p_full_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_name TEXT := regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
    END IF;
    IF length(v_name) < 3 OR length(v_name) > 200 THEN
        RAISE EXCEPTION 'invalid author name';
    END IF;
    RETURN resolve_author_profile(v_name, NULL, NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION find_or_create_author(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION find_or_create_author(TEXT) TO authenticated;

-- Replace the author list of a publication in one call (order = position)
CREATE OR REPLACE FUNCTION set_publication_authors(p_publication_id UUID, p_profile_ids UUID[])
RETURNS void AS $$
BEGIN
    IF NOT can_manage_publication(p_publication_id) THEN
        RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
    END IF;

    DELETE FROM publication_authors WHERE publication_id = p_publication_id;

    INSERT INTO publication_authors (publication_id, profile_id, position)
    SELECT p_publication_id, pid, min(ord)::int
    FROM unnest(p_profile_ids) WITH ORDINALITY AS t(pid, ord)
    GROUP BY pid;

    PERFORM recalculate_publication_authors(p_publication_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION set_publication_authors(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_publication_authors(UUID, UUID[]) TO authenticated;

-- Journal list with publication counts for the public journals page
CREATE OR REPLACE FUNCTION journals_with_counts()
RETURNS TABLE(id UUID, title TEXT, title_en TEXT, issn VARCHAR, publisher TEXT, publication_count BIGINT, citation_count BIGINT) AS $$
    SELECT j.id, j.title, j.title_en, j.issn, j.publisher,
           count(p.id) AS publication_count,
           coalesce(sum(p.citation_count), 0) AS citation_count
    FROM journals j
    LEFT JOIN publications p ON p.journal_id = j.id
    GROUP BY j.id
    ORDER BY count(p.id) DESC, j.title;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;
