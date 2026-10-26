-- ============================================
-- RLS INSERT/UPDATE/DELETE policies
-- ============================================

-- publications: authenticated users can insert
CREATE POLICY "publications_insert" ON publications
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- publications: authors can update their own publications
CREATE POLICY "publications_update" ON publications
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM publication_authors pa
            WHERE pa.publication_id = id
              AND pa.profile_id = auth.uid()
        )
    );

-- publication_authors: authenticated users can insert (when creating a publication)
CREATE POLICY "pub_authors_insert" ON publication_authors
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- publication_authors: only the author themselves or the publication creator can delete
CREATE POLICY "pub_authors_delete" ON publication_authors
    FOR DELETE TO authenticated
    USING (profile_id = auth.uid());

-- journals: only service_role can insert/update (admin)
-- For now, allow authenticated to insert so users can add journals
CREATE POLICY "journals_insert" ON journals
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- raw_references: authenticated users can insert
CREATE POLICY "raw_refs_insert" ON raw_references
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- citations: service_role only (auto-generated), but allow select (already exists)

-- ============================================
-- Seed: Turkmen scientific journals
-- ============================================

INSERT INTO journals (title, title_en, issn, publisher) VALUES
    ('Türkmenistanyň ylymlar akademiýasynyň habarlary', 'Proceedings of the Academy of Sciences of Turkmenistan', '1561-6258', 'Türkmenistanyň Ylymlar akademiýasy'),
    ('Türkmenistanda ylym we tehnika', 'Science and Technology in Turkmenistan', NULL, 'Türkmenistanyň Ylymlar akademiýasy'),
    ('Bilim', 'Education', NULL, 'Türkmenistanyň Bilim ministrligi'),
    ('Saglyk', 'Health', NULL, 'Türkmenistanyň Saglygy goraýyş ministrligi'),
    ('Türkmen döwlet uniwersitetiniň habarçysy', 'Bulletin of Turkmen State University', NULL, 'Magtymguly adyndaky TDU'),
    ('Türkmen döwlet binagärlik-gurluşyk institutynyň ylmy işleri', 'Scientific Works of TSACI', NULL, 'TDBI'),
    ('Türkmenistanyň lukmançylyk ylmy', 'Medical Science of Turkmenistan', NULL, 'TDLU'),
    ('Türkmenistanyň oba hojalygy', 'Agriculture of Turkmenistan', NULL, 'Türkmenistanyň Oba hojalyk ministrligi'),
    ('Kitaphanaçylyk we bibliografiýa', 'Librarianship and Bibliography', NULL, 'Türkmenistanyň Medeniýet ministrligi'),
    ('Miras', 'Heritage', NULL, 'Türkmenistanyň Ylymlar akademiýasy')
ON CONFLICT DO NOTHING;
