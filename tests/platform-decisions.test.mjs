import assert from "node:assert/strict";
import test from "node:test";
import { buildPlatformDecision } from "../lib/platform-decisions.ts";

test("Comunhão preserva approve e reject nos parâmetros nativos", () => {
  assert.deepEqual(buildPlatformDecision("comunhao", "approve", "church-1").body, {
    p_application_id: "church-1", p_decision: "approved", p_review_notes: null,
  });
  assert.deepEqual(buildPlatformDecision("comunhao", "reject", "church-1", "Documentos inválidos").body, {
    p_application_id: "church-1", p_decision: "rejected", p_review_notes: "Documentos inválidos",
  });
});

test("SARCA usa o contrato real da Edge Function", () => {
  assert.deepEqual(buildPlatformDecision("sarca", "approve", "driver-1").body, {
    driverUserId: "driver-1", decision: "approve", rejectionReason: null,
  });
  assert.deepEqual(buildPlatformDecision("sarca", "reject", "driver-1", "Carta de condução inválida").body, {
    driverUserId: "driver-1", decision: "reject", rejectionReason: "Carta de condução inválida",
  });
});

test("TaoMoz preserva os valores do enum KYC", () => {
  assert.equal(buildPlatformDecision("taomoz", "approve", "kyc-1").body.decision, "approved");
  assert.equal(buildPlatformDecision("taomoz", "reject", "kyc-1", "NUIT inválido").body.decision, "rejected");
});

test("rejeição nunca segue sem motivo", () => {
  assert.throws(() => buildPlatformDecision("comunhao", "reject", "church-1"), /REASON_REQUIRED/);
  assert.throws(() => buildPlatformDecision("sarca", "reject", "driver-1"), /REASON_REQUIRED/);
  assert.throws(() => buildPlatformDecision("taomoz", "reject", "kyc-1"), /REASON_REQUIRED/);
});
