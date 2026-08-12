begin;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('church-logos', 'church-logos', false, 2097152,
    array['image/png','image/jpeg','image/webp','image/svg+xml']),
  ('campaign-media', 'campaign-media', false, 5242880,
    array['image/png','image/jpeg','image/webp']),
  ('finance-proofs', 'finance-proofs', false, 5242880,
    array['image/png','image/jpeg','image/webp','application/pdf']),
  ('finance-receipts', 'finance-receipts', false, 5242880,
    array['application/pdf','image/png','image/jpeg']),
  ('church-documents', 'church-documents', false, 10485760,
    array['application/pdf','image/png','image/jpeg','application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('asset-media', 'asset-media', false, 5242880,
    array['image/png','image/jpeg','image/webp','application/pdf']),
  ('request-attachments', 'request-attachments', false, 5242880,
    array['image/png','image/jpeg','image/webp','application/pdf']),
  ('event-media', 'event-media', false, 5242880,
    array['image/png','image/jpeg','image/webp']),
  ('pilot-feedback', 'pilot-feedback', false, 5242880,
    array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict (id) do update set
  name = excluded.name,
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
commit;
