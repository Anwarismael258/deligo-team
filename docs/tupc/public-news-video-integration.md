# Public news video integration — pending public-site source access

The Central supports `news.video_url`, direct MP4/WebM uploads (50 MB), YouTube/Vimeo URLs, image cover/poster, and previews. Existing publication permissions stay in place.

The current public institutional website at `https://www.deligotriunfal.site` is a separate Lovable project. Its deployed `/noticias/$slug` component renders `article.image_url` and `article.body`, but ignores `article.video_url`. This cannot be fixed by saving another database field.

After opening the actual Lovable source:

1. Reuse `components/NewsMedia.tsx` and `lib/news-media.ts` from this repository (adjust the import alias only if required).
2. Preserve the existing Supabase reader, RLS, publication filters, title, author, date, body and route.
3. Add optional `video_url: string | null` to the public article type if missing.
4. Replace the article's cover-only media block with `<NewsMedia title={article.title} imageUrl={article.image_url} videoUrl={article.video_url} />`.
5. Render the cover image as video poster for MP4/WebM. For YouTube and Vimeo use only normalized embeds from the helper. No raw HTML, autoplay or new external-player SDK is needed.
6. Keep list cards lightweight, using the cover image and an optional video indicator; play the video on the article detail page.
7. Verify published photo-only, video-only and photo-plus-video articles. Verify private drafts stay hidden. Publish the existing site without changing its domain or audience.

Do not claim public video playback is live before this source edit is published and verified. No existing article should be modified just to manufacture a public test.
