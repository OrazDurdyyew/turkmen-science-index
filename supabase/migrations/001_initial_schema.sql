-- ============================================
-- TSI: Initial Schema Migration
-- ============================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- 1. JOURNALS
-- ============================================
CREATE TABLE journals (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT NOT NULL,
    title_en    TEXT,
    issn        VARCHAR(9) UNIQUE,
    publisher   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_journals_title_trgm ON journals USING GIN (title gin_trgm_ops);

-- ============================================
-- 2. PROFILES (authors)
-- ============================================
CREATE TABLE profiles (
    id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name           TEXT NOT NULL,
    full_name_en        TEXT,
    institution         TEXT,
    orcid               VARCHAR(19) UNIQUE,
    h_index             INT NOT NULL DEFAULT 0,
    i10_index           INT NOT NULL DEFAULT 0,
    h_index_updated_at  TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_full_name_trgm ON profiles USING GIN (full_name gin_trgm_ops);
CREATE INDEX idx_profiles_institution ON profiles (institution);

-- ============================================
-- 3. PUBLICATIONS
-- ============================================
CREATE TABLE publications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    title_en        TEXT,
    abstract        TEXT,
    journal_id      UUID REFERENCES journals(id) ON DELETE SET NULL,
    published_date  DATE,
    pdf_path        TEXT,
    doi             VARCHAR(255) UNIQUE,
    language        VARCHAR(2) DEFAULT 'tk',
    citation_count  INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_publications_fts ON publications
    USING GIN (to_tsvector('russian', coalesce(title, '') || ' ' || coalesce(abstract, '')));
CREATE INDEX idx_publications_title_trgm ON publications USING GIN (title gin_trgm_ops);
CREATE INDEX idx_publications_journal ON publications (journal_id);
CREATE INDEX idx_publications_date ON publications (published_date DESC);

-- ============================================
-- 4. PUBLICATION_AUTHORS (M2M)
-- ============================================
CREATE TABLE publication_authors (
    publication_id      UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    profile_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    position            INT NOT NULL DEFAULT 1,
    is_corresponding    BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (publication_id, profile_id)
);

CREATE INDEX idx_pub_authors_profile ON publication_authors (profile_id);

-- ============================================
-- 5. CITATIONS
-- ============================================
CREATE TABLE citations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    target_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_publication_id, target_publication_id),
    CHECK (source_publication_id != target_publication_id)
);

CREATE INDEX idx_citations_target ON citations (target_publication_id);
CREATE INDEX idx_citations_source ON citations (source_publication_id);

-- ============================================
-- 6. RAW_REFERENCES
-- ============================================
CREATE TABLE raw_references (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    raw_text                TEXT NOT NULL,
    parsed_title            TEXT,
    parsed_authors          TEXT,
    parsed_year             INT,
    matched_publication_id  UUID REFERENCES publications(id) ON DELETE SET NULL,
    match_score             REAL,
    status                  VARCHAR(10) NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'matched', 'unmatched')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    matched_at              TIMESTAMPTZ
);

CREATE INDEX idx_raw_refs_status ON raw_references (status) WHERE status = 'pending';
CREATE INDEX idx_raw_refs_source ON raw_references (source_publication_id);
CREATE INDEX idx_raw_refs_matched ON raw_references (matched_publication_id) WHERE matched_publication_id IS NOT NULL;

-- ============================================
-- TRIGGERS & FUNCTIONS
-- ============================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_publications_updated_at BEFORE UPDATE ON publications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Auto-update citation_count
CREATE OR REPLACE FUNCTION update_citation_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE publications
        SET citation_count = citation_count + 1
        WHERE id = NEW.target_publication_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE publications
        SET citation_count = citation_count - 1
        WHERE id = OLD.target_publication_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_citation_count
AFTER INSERT OR DELETE ON citations
FOR EACH ROW EXECUTE FUNCTION update_citation_count();

-- Recalculate h-index for a profile
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
$$ LANGUAGE plpgsql;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (NEW.id, coalesce(NEW.raw_user_meta_data->>'full_name', ''));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================
-- RLS POLICIES
-- ============================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE publication_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE citations ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_references ENABLE ROW LEVEL SECURITY;

-- profiles
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);

-- publications
CREATE POLICY "publications_select" ON publications FOR SELECT USING (true);

-- journals
CREATE POLICY "journals_select" ON journals FOR SELECT USING (true);

-- publication_authors
CREATE POLICY "pub_authors_select" ON publication_authors FOR SELECT USING (true);

-- citations
CREATE POLICY "citations_select" ON citations FOR SELECT USING (true);

-- raw_references
CREATE POLICY "raw_refs_select" ON raw_references FOR SELECT USING (true);
