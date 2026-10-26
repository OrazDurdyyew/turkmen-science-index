-- ============================================
-- SEARCH: Full-text + fuzzy search functions
-- ============================================

-- Search publications by query (FTS + trigram fallback)
CREATE OR REPLACE FUNCTION search_publications(
    p_query TEXT,
    p_journal_id UUID DEFAULT NULL,
    p_year_from INT DEFAULT NULL,
    p_year_to INT DEFAULT NULL,
    p_language VARCHAR DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
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
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.title,
        p.abstract,
        p.published_date,
        p.citation_count,
        p.language,
        j.title AS journal_title,
        (
            SELECT string_agg(pr.full_name, ', ' ORDER BY pa.position)
            FROM publication_authors pa
            JOIN profiles pr ON pr.id = pa.profile_id
            WHERE pa.publication_id = p.id
        ) AS authors,
        CASE
            -- Try FTS first
            WHEN p_query IS NOT NULL AND length(p_query) > 0 THEN
                GREATEST(
                    ts_rank(
                        to_tsvector('russian', coalesce(p.title, '') || ' ' || coalesce(p.abstract, '')),
                        plainto_tsquery('russian', p_query)
                    ),
                    similarity(p.title, p_query)
                )
            ELSE 1.0
        END AS rank
    FROM publications p
    LEFT JOIN journals j ON j.id = p.journal_id
    WHERE
        -- Text search: FTS OR trigram
        (
            p_query IS NULL
            OR length(p_query) = 0
            OR to_tsvector('russian', coalesce(p.title, '') || ' ' || coalesce(p.abstract, ''))
                @@ plainto_tsquery('russian', p_query)
            OR similarity(p.title, p_query) >= 0.2
        )
        -- Filters
        AND (p_journal_id IS NULL OR p.journal_id = p_journal_id)
        AND (p_year_from IS NULL OR extract(year FROM p.published_date) >= p_year_from)
        AND (p_year_to IS NULL OR extract(year FROM p.published_date) <= p_year_to)
        AND (p_language IS NULL OR p.language = p_language)
    ORDER BY rank DESC, p.citation_count DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Search authors by name (trigram similarity)
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
            THEN similarity(pr.full_name, p_query)
            ELSE 1.0
        END AS rank
    FROM profiles pr
    WHERE
        p_query IS NULL
        OR length(p_query) = 0
        OR similarity(pr.full_name, p_query) >= 0.15
    ORDER BY rank DESC, pr.h_index DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Autocomplete: fast prefix-based suggestions
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
    LIMIT p_limit;

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
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

-- Grant access
GRANT EXECUTE ON FUNCTION search_publications TO authenticated, anon;
GRANT EXECUTE ON FUNCTION search_authors TO authenticated, anon;
GRANT EXECUTE ON FUNCTION autocomplete TO authenticated, anon;
