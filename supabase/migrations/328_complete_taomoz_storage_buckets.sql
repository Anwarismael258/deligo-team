begin;
insert into storage.buckets (id,name,public)
values
  ('avatars','avatars',true),
  ('delivery-proofs','delivery-proofs',false),
  ('kyc-documents','kyc-documents',false),
  ('product-images','product-images',true),
  ('store-assets','store-assets',true)
on conflict(id) do update set
  name=excluded.name,
  public=excluded.public;
commit;
