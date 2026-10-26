-- ============================================
-- MATCHING ENGINE: pg_trgm fuzzy matching
-- ============================================

-- Match pending raw_references against publications
CREATE OR REPLACE FUNCTION match_raw_references(
    p_threshold REAL DEFAULT 0.3,
    p_batch_size INT DEFAULT 500
)
RETURNS TABLE(matched_count INT, total_pending INT) AS $$
DECLARE
    v_matched INT := 0;
    v_total INT;
    v_ref RECORD;
    v_best_match RECORD;
BEGIN
    SELECT count(*) INTO v_total
    FROM raw_references WHERE status = 'pending';

    FOR v_ref IN
        SELECT id, parsed_title, parsed_authors, parsed_year, source_publication_id
        FROM raw_references
        WHERE status = 'pending'
        LIMIT p_batch_size
    LOOP
        -- Skip if no parsed title
        IF v_ref.parsed_title IS NULL OR length(v_ref.parsed_title) < 5 THEN
            UPDATE raw_references
            SET status = 'unmatched', matched_at = now()
            WHERE id = v_ref.id;
            CONTINUE;
        END IF;

        -- Find best matching publication by title similarity
        SELECT
            p.id AS pub_id,
            similarity(v_ref.parsed_title, p.title) AS title_sim
        INTO v_best_match
        FROM publications p
        WHERE p.id != v_ref.source_publication_id
          AND similarity(v_ref.parsed_title, p.title) >= p_threshold
        ORDER BY similarity(v_ref.parsed_title, p.title) DESC
        LIMIT 1;

        IF v_best_match IS NOT NULL AND v_best_match.pub_id IS NOT NULL THEN
            -- Boost score if year matches
            DECLARE
                v_final_score REAL := v_best_match.title_sim;
                v_pub_year INT;
            BEGIN
                SELECT extract(year FROM published_date)::int INTO v_pub_year
                FROM publications WHERE id = v_best_match.pub_id;

                IF v_ref.parsed_year IS NOT NULL AND v_pub_year IS NOT NULL
                   AND v_ref.parsed_year = v_pub_year THEN
                    v_final_score := least(v_final_score + 0.1, 1.0);
                END IF;

                -- Update raw_reference
                UPDATE raw_references
                SET matched_publication_id = v_best_match.pub_id,
                    match_score = v_final_score,
                    status = 'matched',
                    matched_at = now()
                WHERE id = v_ref.id;

                -- Create citation if not exists
                INSERT INTO citations (source_publication_id, target_publication_id)
                VALUES (v_ref.source_publication_id, v_best_match.pub_id)
                ON CONFLICT DO NOTHING;

                v_matched := v_matched + 1;
            END;
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
-- TRIGGER: rematch when new publication arrives
-- ============================================

-- When a new publication is inserted, re-check unmatched references
CREATE OR REPLACE FUNCTION rematch_on_new_publication()
RETURNS TRIGGER AS $$
BEGIN
    -- Reset unmatched refs whose parsed_title is similar to the new publication
    UPDATE raw_references
    SET status = 'pending'
    WHERE status = 'unmatched'
      AND parsed_title IS NOT NULL
      AND similarity(parsed_title, NEW.title) >= 0.3;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER trg_rematch_on_new_pub
AFTER INSERT ON publications
FOR EACH ROW EXECUTE FUNCTION rematch_on_new_publication();

-- ============================================
-- FUNCTION: recalculate h-index for all authors
-- ============================================

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
    LOOP
        PERFORM recalculate_h_index(v_profile_id);
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- CRON JOBS via pg_cron (if available)
-- ============================================

-- pg_cron may not be available in local Supabase
-- These can be called manually or via Edge Functions

-- Alternative: create wrapper functions callable via Supabase RPC

-- Run matching every 10 minutes
CREATE OR REPLACE FUNCTION run_matching()
RETURNS json AS $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT * INTO v_result FROM match_raw_references(0.3, 500);
    RETURN json_build_object(
        'matched', v_result.matched_count,
        'pending', v_result.total_pending
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Run h-index recalculation
CREATE OR REPLACE FUNCTION run_h_index_update()
RETURNS json AS $$
DECLARE
    v_count INT;
BEGIN
    SELECT recalculate_all_h_indexes() INTO v_count;
    RETURN json_build_object('profiles_updated', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- RLS: allow RPC calls for authenticated users
-- ============================================

-- Grant execute to authenticated users (read-only operations)
GRANT EXECUTE ON FUNCTION run_matching() TO authenticated;
GRANT EXECUTE ON FUNCTION run_h_index_update() TO authenticated;
