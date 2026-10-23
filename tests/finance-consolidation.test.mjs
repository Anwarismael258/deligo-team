import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";

const source = fs.readFileSync("lib/finance-consolidation.ts", "utf8");

test("matriz financeira cobre as cinco plataformas consolidadas", () => {
  for (const platform of ["DeliGo Eats", "SARCA", "Mestre24", "Comunhão", "DeliGo Market"]) assert.match(source, new RegExp(platform.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(source, /primarySource/);
  assert.match(source, /validationSource/);
  assert.match(source, /accountingPeriod/);
});

test("reconciliação interna distingue divergência, pendência e fonte insuficiente", () => {
  for (const state of ["RECONCILIADO_INTERNAMENTE", "DIVERGENTE", "PENDENTE", "FONTE_INSUFICIENTE", "NAO_APLICAVEL"]) assert.match(source, new RegExp(state));
  assert.match(source, /duplicateEventIds/);
  assert.match(source, /unmatchedMovements/);
  assert.match(source, /stalePendingMovements/);
});

test("consolidação impede dupla contagem por identificador e origem já incluída", () => {
  assert.match(source, /seen = new Set/);
  assert.match(source, /alreadyIncluded/);
  assert.match(source, /seen\.has\(entry\.id\)/);
});
