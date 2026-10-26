-- Duplicate detection for the parser: same DOI or same title (case-insensitive, also vs title_en)
CREATE OR REPLACE FUNCTION find_duplicate_publication(p_title TEXT, p_doi TEXT DEFAULT NULL)
RETURNS UUID AS $$
    SELECT id FROM publications
    WHERE (p_doi IS NOT NULL AND lower(doi) = lower(p_doi))
       OR lower(title) = lower(trim(p_title))
       OR lower(title_en) = lower(trim(p_title))
    ORDER BY (p_doi IS NOT NULL AND lower(doi) = lower(p_doi)) DESC
    LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION find_duplicate_publication(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION find_duplicate_publication(TEXT, TEXT) TO service_role;

CREATE INDEX IF NOT EXISTS idx_publications_title_lower ON publications (lower(title));

-- Unclaimed author profiles left without publications (after deletions) are noise
CREATE OR REPLACE FUNCTION cleanup_orphan_profiles()
RETURNS INT AS $$
DECLARE
    v_count INT;
BEGIN
    DELETE FROM profiles p
    WHERE p.user_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM publication_authors pa WHERE pa.profile_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM profile_claims c WHERE c.profile_id = p.id AND c.status = 'pending');
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION cleanup_orphan_profiles() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('tsi-orphan-profiles', '30 3 * * *', 'SELECT public.cleanup_orphan_profiles()');
