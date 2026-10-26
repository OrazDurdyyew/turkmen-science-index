-- Create storage bucket for PDF papers
INSERT INTO storage.buckets (id, name, public)
VALUES ('papers', 'papers', false)
ON CONFLICT DO NOTHING;

-- Allow authenticated users to upload PDFs
CREATE POLICY "papers_upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'papers');

-- Allow authenticated users to read PDFs
CREATE POLICY "papers_read" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'papers');
