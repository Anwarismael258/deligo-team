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
  assert.match(html, /A preparar a Central/);
  assert.match(html, /A validar a sessão e o cargo/);
  assert.doesNotMatch(html, /A ligar ao backend Deligo Staging/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("renderiza rotas de módulos", async () => {
  const response = await render("/financas");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
});

test("protege a navegação antes de validar a sessão e o cargo", async () => {
  const response = await render();
  const html = await response.text();
  assert.match(html, /A validar a sessão e o cargo/);
  assert.doesNotMatch(html, /class="navItem|Simular perfil/);
});

test("renderiza o login corporativo sem registo público", async () => {
  const response = await render("/login");
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /Número de telefone/);
  assert.match(html, /Palavra-passe/);
  assert.match(html, /deligo-icon\.png/);
  assert.match(html, /Contacte Recursos Humanos ou a Administração/);
  assert.doesNotMatch(html, /Criar conta|Registar-se/);
});
