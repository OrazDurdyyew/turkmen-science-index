-- Security / RLS regression test. Runs in a transaction and rolls everything back.
-- Usage: docker exec -i supabase_db_tsi psql -U postgres -v ON_ERROR_STOP=1 < supabase/tests/security_test.sql

BEGIN;

-- Fixtures: a regular user, an admin, an unclaimed author, a publication by someone else
INSERT INTO auth.users (id, email, raw_user_meta_data, aud, role)
VALUES
    ('00000000-0000-0000-0000-00000000000a', 'user@tsi.test', '{"full_name":"Обычный Пользователь"}', 'authenticated', 'authenticated'),
    ('00000000-0000-0000-0000-00000000000b', 'admin@tsi.test', '{"full_name":"Админ Админов"}', 'authenticated', 'authenticated');
UPDATE profiles SET role = 'admin' WHERE id = '00000000-0000-0000-0000-00000000000b';

INSERT INTO profiles (id, full_name) VALUES ('00000000-0000-0000-0000-0000000000c1', 'Незарегистрированный Автор');
INSERT INTO publications (id, title) VALUES
    ('00000000-0000-0000-0000-0000000000d1', 'Чужая статья о тестировании'),
    ('00000000-0000-0000-0000-0000000000d2', 'Цитирующая статья');
INSERT INTO publication_authors (publication_id, profile_id) VALUES
    ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1');
INSERT INTO raw_references (id, source_publication_id, raw_text, parsed_title, status) VALUES
    ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d2',
     'Автор Н. Чужая статья о тестировании. 2020', 'Чужая статья о тестировании', 'unmatched');

CREATE TEMP TABLE results (name TEXT, ok BOOLEAN);
GRANT ALL ON results TO authenticated, anon;

CREATE FUNCTION pg_temp.as_user(p_uid UUID) RETURNS void AS $$
BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
END $$ LANGUAGE plpgsql;

-- ---------- regular user ----------
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000a');

UPDATE profiles SET role = 'admin', h_index = 99, full_name = 'Новое Имя'
WHERE id = '00000000-0000-0000-0000-00000000000a';
INSERT INTO results SELECT 'user cannot escalate role / fake h-index',
    (SELECT role = 'user' AND h_index = 0 AND full_name = 'Новое Имя'
     FROM profiles WHERE id = '00000000-0000-0000-0000-00000000000a');

UPDATE profiles SET full_name = 'Взлом' WHERE id = '00000000-0000-0000-0000-0000000000c1';
INSERT INTO results SELECT 'user cannot edit unclaimed profile',
    (SELECT full_name = 'Незарегистрированный Автор' FROM profiles WHERE id = '00000000-0000-0000-0000-0000000000c1');

UPDATE publications SET title = 'Взлом' WHERE id = '00000000-0000-0000-0000-0000000000d1';
INSERT INTO results SELECT 'user cannot edit foreign publication',
    (SELECT title = 'Чужая статья о тестировании' FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d1');

DO $$ BEGIN
    INSERT INTO publication_authors (publication_id, profile_id)
    VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000000a');
    INSERT INTO results VALUES ('user cannot attach self to foreign publication', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('user cannot attach self to foreign publication', true);
END $$;

INSERT INTO publications (id, title, citation_count)
VALUES ('00000000-0000-0000-0000-0000000000d3', 'Моя статья', 500);
INSERT INTO publication_authors (publication_id, profile_id)
VALUES ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-00000000000a');
INSERT INTO results SELECT 'user can add own publication, citation_count forced to 0',
    (SELECT citation_count = 0 AND created_by = '00000000-0000-0000-0000-00000000000a'
     FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d3');

DO $$ BEGIN
    INSERT INTO journals (title) VALUES ('Левый журнал');
    INSERT INTO results VALUES ('user cannot create journals', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('user cannot create journals', true);
END $$;

DO $$ BEGIN
    PERFORM run_matching();
    INSERT INTO results VALUES ('user cannot run matching', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('user cannot run matching', true);
END $$;

DO $$ BEGIN
    PERFORM admin_stats();
    INSERT INTO results VALUES ('user cannot read admin stats', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('user cannot read admin stats', true);
END $$;

INSERT INTO profile_claims (profile_id, profile_name, user_id)
VALUES ('00000000-0000-0000-0000-0000000000c1', 'Незарегистрированный Автор', '00000000-0000-0000-0000-00000000000a');
INSERT INTO results SELECT 'user can claim unclaimed profile',
    (SELECT count(*) = 1 FROM profile_claims WHERE user_id = '00000000-0000-0000-0000-00000000000a');

-- ---------- admin ----------
RESET role;
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000b');

INSERT INTO results SELECT 'admin reads stats', (SELECT (admin_stats()->>'publications')::int >= 3);

INSERT INTO journals (title) VALUES ('Журнал от админа');
INSERT INTO results SELECT 'admin creates journals', EXISTS (SELECT 1 FROM journals WHERE title = 'Журнал от админа');

SELECT admin_link_reference('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1');
INSERT INTO results SELECT 'admin manual link creates citation',
    (SELECT citation_count = 1 FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d1');
INSERT INTO results SELECT 'manual link recalculates h-index',
    (SELECT h_index = 1 FROM profiles WHERE id = '00000000-0000-0000-0000-0000000000c1');

SELECT admin_set_reference_status('00000000-0000-0000-0000-0000000000e1', 'rejected');
INSERT INTO results SELECT 'reject removes orphan citation',
    (SELECT citation_count = 0 FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d1');
INSERT INTO results SELECT 'reject resets h-index',
    (SELECT h_index = 0 FROM profiles WHERE id = '00000000-0000-0000-0000-0000000000c1');

SELECT admin_resolve_claim(
    (SELECT id FROM profile_claims WHERE user_id = '00000000-0000-0000-0000-00000000000a'), true);
INSERT INTO results SELECT 'approved claim moves authorship to user',
    EXISTS (SELECT 1 FROM publication_authors
            WHERE publication_id = '00000000-0000-0000-0000-0000000000d1'
              AND profile_id = '00000000-0000-0000-0000-00000000000a');
INSERT INTO results SELECT 'approved claim removes unclaimed profile',
    NOT EXISTS (SELECT 1 FROM profiles WHERE id = '00000000-0000-0000-0000-0000000000c1');
INSERT INTO results SELECT 'claim history kept',
    (SELECT status = 'approved' FROM profile_claims WHERE user_id = '00000000-0000-0000-0000-00000000000a');

-- ---------- review regressions ----------
-- A user's own citing publication: deleting it must decrement the target's citation_count
RESET role;
INSERT INTO publications (id, title, created_by) VALUES
    ('00000000-0000-0000-0000-0000000000d4', 'Цитирующая статья пользователя', '00000000-0000-0000-0000-00000000000a');
INSERT INTO citations (source_publication_id, target_publication_id)
VALUES ('00000000-0000-0000-0000-0000000000d4', '00000000-0000-0000-0000-0000000000d1');
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
DELETE FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d4';
INSERT INTO results SELECT 'deleting own citing paper decrements citation_count',
    (SELECT citation_count = (SELECT count(*) FROM citations WHERE target_publication_id = p.id)
     FROM publications p WHERE id = '00000000-0000-0000-0000-0000000000d1');

-- A user renamed to someone else's name is not picked by automatic author resolution
UPDATE profiles SET full_name = 'Известный Учёный Иванович' WHERE id = '00000000-0000-0000-0000-00000000000a';
INSERT INTO results SELECT 'renamed user not auto-resolved as author',
    find_or_create_author('Известный Учёный Иванович') != '00000000-0000-0000-0000-00000000000a';

-- References can only be queued, not pre-matched
DO $$ BEGIN
    INSERT INTO raw_references (source_publication_id, raw_text, status, matched_publication_id, match_score)
    VALUES ('00000000-0000-0000-0000-0000000000d3', 'fake', 'matched', '00000000-0000-0000-0000-0000000000d1', 1);
    INSERT INTO results VALUES ('user cannot insert pre-matched reference', false);
EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO results VALUES ('user cannot insert pre-matched reference', true);
END $$;

-- Search page size is clamped
INSERT INTO results SELECT 'search limit clamped',
    (SELECT count(*) <= 100 FROM search_authors('', 100000, 0));

-- Resolution never rewrites a registered profile
RESET role;
SELECT resolve_author_profile('Админ Админов', 'John Smith', 'Fake Institute');
INSERT INTO results SELECT 'resolver does not touch registered profiles',
    (SELECT full_name_en IS NULL AND institution IS NULL FROM profiles WHERE id = '00000000-0000-0000-0000-00000000000b');

-- Undoing a wrong match sticks even when a similar publication appears later
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
INSERT INTO publications (id, title) VALUES ('00000000-0000-0000-0000-0000000000d5', 'Совершенно другая статья');
INSERT INTO raw_references (id, source_publication_id, raw_text, parsed_title, status) VALUES
    ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000d5',
     'Чужая статья о тестировании', 'Чужая статья о тестировании', 'pending');
RESET role;
SELECT match_raw_references();
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
SELECT admin_set_reference_status('00000000-0000-0000-0000-0000000000e2', 'unmatched');
RESET role;
INSERT INTO publications (title) VALUES ('Чужая статья о тестировании (копия)');
SELECT match_raw_references();
INSERT INTO results SELECT 'unmatched undo is not re-matched to the same target',
    (SELECT matched_publication_id IS DISTINCT FROM '00000000-0000-0000-0000-0000000000d1'
     FROM raw_references WHERE id = '00000000-0000-0000-0000-0000000000e2');

-- Deleting a cited publication returns references to the pool
SELECT pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
SELECT admin_link_reference('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000d1');
DELETE FROM publications WHERE id = '00000000-0000-0000-0000-0000000000d1';
INSERT INTO results SELECT 'deleting cited publication releases its references',
    (SELECT status = 'unmatched' AND matched_publication_id IS NULL
     FROM raw_references WHERE id = '00000000-0000-0000-0000-0000000000e2');

-- ---------- anonymous ----------
RESET role;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SET LOCAL role anon;
INSERT INTO results SELECT 'anon reads public stats', (SELECT (public_stats()->>'publications')::int >= 3);
RESET role;

SELECT CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result, name FROM results;
SELECT count(*) FILTER (WHERE NOT ok OR ok IS NULL) AS failures FROM results;

ROLLBACK;
