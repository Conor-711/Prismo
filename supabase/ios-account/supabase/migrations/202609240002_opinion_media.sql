begin;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
  values ('bsmart-opinion-media', 'bsmart-opinion-media', true, 4194304,
    array['image/jpeg', 'image/png'])
  on conflict(id) do nothing;

commit;
