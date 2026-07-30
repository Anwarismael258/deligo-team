import type { EmployeeId } from "./identity";

export type AuditAction =
  | "AUTH_LOGIN_SUCCEEDED"
  | "AUTH_LOGIN_FAILED"
  | "AUTH_2FA_CHALLENGED"
  | "ACCESS_ALLOWED"
  | "ACCESS_DENIED"
  | "PERMISSION_GRANTED"
  | "PERMISSION_REVOKED"
  | "APPROVAL_SUBMITTED"
  | "APPROVAL_DECIDED"
  | "RESERVED_MATTER_SUBMITTED"
  | "RESERVED_MATTER_APPROVED"
  | "OWNERSHIP_RECORD_VIEWED"
  | "OWNERSHIP_CHANGE_ATTEMPTED";

export type AuditEvent = {
  id: string;
  occurredAt: string;
  actorEmployeeId: EmployeeId | null;
  action: AuditAction;
  targetType: string;
  targetId: string | null;
  legalEntityId: string;
  platform: string | null;
  permission: string | null;
  outcome: "SUCCESS" | "DENIED" | "ERROR";
  correlationId: string;
  metadata: Record<string, string | number | boolean | null>;
};

export type AuditWriter = {
  append(event: Readonly<AuditEvent>): Promise<void>;
};

export class FrozenAuditWriter implements AuditWriter {
  async append(): Promise<void> {
    throw new Error("BACKEND_FROZEN");
  }
}
