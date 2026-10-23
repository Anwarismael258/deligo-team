/** Canonical role vocabulary used by Central HQ server authorization. */
export type CanonicalCorporateRole =
  | "SUPER_ADMIN" | "FINANCE" | "SUPERVISOR" | "ACCOUNTING"
  | "HUMAN_RESOURCES" | "LEGAL" | "COMPLIANCE" | "OPERATIONS"
  | "TECHNOLOGY" | "MARKETING" | "FIELD" | "CUSTOMER_SUPPORT"
  | "PARTNER_ACQUISITION" | "AMBASSADOR" | "PROCUREMENT"
  | "ASSETS_LOGISTICS" | "EMPLOYEE";

const aliases: Record<string, CanonicalCorporateRole> = {
  ADMIN: "SUPER_ADMIN", ADMINISTRATOR: "SUPER_ADMIN", CEO: "SUPER_ADMIN", EXECUTIVE: "SUPER_ADMIN",
  SUPPORT: "CUSTOMER_SUPPORT", SUPPORT_AGENT: "CUSTOMER_SUPPORT", OPERATIONS_SUPERVISOR: "SUPERVISOR",
};

export function canonicalCorporateRole(value: unknown): CanonicalCorporateRole {
  const role = String(value || "").trim().toUpperCase();
  return aliases[role] || (role as CanonicalCorporateRole) || "EMPLOYEE";
}
