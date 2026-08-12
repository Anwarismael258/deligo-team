import type { PlatformBackend } from "./platform-backends.ts";

export type PlatformDecision = "approve" | "reject" | "correction";

export function buildPlatformDecision(
  platform: PlatformBackend,
  decision: PlatformDecision,
  id: string,
  reason = "",
) {
  if (!id.trim()) throw new Error("PLATFORM_RECORD_ID_REQUIRED");
  if ((decision === "reject" || decision === "correction") && !reason.trim()) {
    throw new Error("PLATFORM_DECISION_REASON_REQUIRED");
  }

  if (platform === "comunhao") {
    return {
      transport: "rpc" as const,
      name: "review_church_application",
      body: {
        p_application_id: id,
        p_decision: decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "changes_requested",
        p_review_notes: reason.trim() || null,
      },
    };
  }

  if (platform === "sarca") {
    if (decision === "correction") throw new Error("SARCA_CORRECTION_NOT_SUPPORTED");
    return {
      transport: "function" as const,
      name: "admin-review-driver-onboarding",
      body: {
        driverUserId: id,
        decision,
        rejectionReason: reason.trim() || null,
      },
    };
  }

  if (platform === "taomoz") {
    if (decision === "correction") throw new Error("TAOMOZ_CORRECTION_NOT_SUPPORTED");
    return {
      transport: "rpc" as const,
      name: "admin_review_kyc",
      body: {
        submission_id: id,
        decision: decision === "approve" ? "approved" : "rejected",
        reason: reason.trim() || null,
      },
    };
  }

  if (platform === "mestre24") {
    if (decision === "correction") throw new Error("MESTRE24_CORRECTION_NOT_SUPPORTED");
    return {
      transport: "rest" as const,
      name: `kyc_verifications?id=eq.${encodeURIComponent(id)}`,
      body: {
        status: decision === "approve" ? "approved" : "rejected",
        reviewed_at: new Date().toISOString(),
        reason: reason.trim() || null,
      },
    };
  }

  return {
    transport: "rest" as const,
    name: `profiles?id=eq.${encodeURIComponent(id)}`,
    body: {
      kyc_status: decision === "approve" ? "approved" : decision === "reject" ? "rejected" : "pending",
      kyc_rejection_reason: reason.trim() || null,
    },
  };
}
