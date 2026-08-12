import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("corporate contract covers every current or planned platform", async () => {
  const source = await readFile(new URL("../lib/central-platform-contract.ts", import.meta.url), "utf8");
  for (const code of ["DELIGO", "SARCA", "DELIGO_MARKETING", "COMUNHAO", "MESTRE24", "EXPLOREMOZ"]) {
    assert.match(source, new RegExp(`code: "${code}"`));
  }
  assert.match(source, /sourceEventId/);
  assert.match(source, /grossAmount/);
  assert.match(source, /paymentStatus/);
});
