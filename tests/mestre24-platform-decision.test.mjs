import assert from "node:assert/strict";
import test from "node:test";
import { buildPlatformDecision } from "../lib/platform-decisions.ts";

test("Mestre24 decide apenas o KYC e nunca altera o perfil directamente", () => {
  const operation = buildPlatformDecision("mestre24", "approve", "kyc-1");
  assert.equal(operation.transport, "rest");
  assert.equal(operation.name, "kyc_verifications?id=eq.kyc-1");
  assert.equal(operation.body.status, "approved");
  assert.throws(
    () => buildPlatformDecision("mestre24", "correction", "kyc-1", "Documento ilegível"),
    /MESTRE24_CORRECTION_NOT_SUPPORTED/,
  );
});
