-- Matching: recalculate h-index of the cited authors as soon as a citation appears,
-- instead of waiting for the hourly job (which still runs as a safety net).
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

            -- Authors of the cited work see the new citation in their h-index right away
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

REVOKE EXECUTE ON FUNCTION match_raw_references(REAL, INT) FROM PUBLIC, anon, authenticated;
