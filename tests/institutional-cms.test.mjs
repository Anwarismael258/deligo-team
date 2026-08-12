import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const migration = await readFile(new URL("../supabase/migrations/378_institutional_cms.sql", import.meta.url), "utf8");
const api = await readFile(new URL("../app/api/institutional/news/route.ts", import.meta.url), "utf8");

test("CMS institucional cria as tabelas públicas esperadas sem tocar em operações", () => {
  for (const table of ["news", "heroes", "job_openings", "partners", "events", "team_members", "gallery", "statistics", "settings"]) assert.match(migration, new RegExp(`create table if not exists public\\.${table}`));
  assert.doesNotMatch(migration, /alter table public\.(orders|couriers|restaurants|wallets)/i);
});

test("RLS permite apenas leitura anon de publicação institucional", () => {
  assert.match(migration, /institutional_news_public_read[\s\S]*published=true/);
  assert.match(migration, /revoke all on public\.news[\s\S]* from anon/);
  assert.match(migration, /grant select on public\.news/);
});

test("API usa permissões granulares, auditoria e nunca recebe service role do browser", () => {
  for (const permission of ["news.create", "news.edit", "news.review", "news.approve", "news.publish", "news.schedule", "news.archive", "news.delete"]) assert.match(api, new RegExp(`\\"${permission}\\"`));
  assert.match(api, /news\.created/);
  assert.match(api, /news\.published/);
  assert.doesNotMatch(api, /NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY/);
});
