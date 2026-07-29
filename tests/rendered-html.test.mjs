import assert from "node:assert/strict";
import test from "node:test";

async function render(pathname = "/") {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}-${pathname}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request(`http://localhost${pathname}`, { headers: { accept: "text/html" } }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("renderiza a Central HQ em português", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /<title>DeliGo Triunfal HQ<\/title>/i);
  assert.match(html, /Visão geral do grupo/);
  assert.match(html, /integrações com o backend temporariamente desligadas/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("renderiza rotas de módulos", async () => {
  const response = await render("/financas");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
});

test("inclui navegação e simulação de perfis", async () => {
  const response = await render();
  const html = await response.text();
  assert.match(html, /Simular perfil/);
  assert.match(html, /Anwar/);
  assert.match(html, /Sara/);
  assert.match(html, /Sansão/);
  assert.match(html, /Técnico IT/);
});
