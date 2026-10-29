-- Allow videos only in the existing public institutional-news bucket.
update storage.buckets set file_size_limit=greatest(coalesce(file_size_limit,0),52428800),allowed_mime_types=(select array_agg(distinct mime) from unnest(coalesce(allowed_mime_types,array['image/jpeg','image/png','image/webp','application/pdf'])||array['video/mp4','video/webm']) as mime) where id='institutional-news';
