import type { PlatformSlug } from "./contracts";

export type EmployeeId = `DG-${string}`;
export type CorporateRole =
  | "SUPER_ADMIN"
  | "ADMINISTRATOR"
  | "DEPARTMENT_MANAGER"
  | "SUPERVISOR"
  | "EMPLOYEE"
  | "EXTERNAL_COLLABORATOR";

export type Department =
  | "EXECUTIVE"
  | "FINANCE"
  | "ACCOUNTING"
  | "HUMAN_RESOURCES"
  | "LEGAL"
  | "COMPLIANCE_RISK"
  | "TECHNOLOGY"
  | "PROCUREMENT"
  | "ASSETS"
  | "OPERATIONS"
  | "MARKETING"
  | "FIELD"
  | "CUSTOMER_SUPPORT"
  | "PARTNER_ACQUISITION";

export type CorporateIdentity = {
  employeeId: EmployeeId;
  displayName: string;
  phoneE164: `+${string}`;
  corporateEmail: string | null;
  department: Department;
  jobTitle: string;
  role: CorporateRole;
  status: "INVITED" | "ACTIVE" | "SUSPENDED" | "OFFBOARDED";
  platforms: PlatformSlug[];
  validFrom: string;
  validUntil: string | null;
};

export type AuthenticationPolicy = {
  primaryIdentifier: "PHONE";
  futureIdentifiers: readonly ["CORPORATE_EMAIL"];
  passwordRequired: true;
  selfRegistrationAllowed: false;
  secondFactor: "AUTHENTICATOR_OR_OTP";
  recovery: readonly ["SMS_OTP", "RECOVERY_CODES"];
};

export const authenticationPolicy: AuthenticationPolicy = {
  primaryIdentifier: "PHONE",
  futureIdentifiers: ["CORPORATE_EMAIL"],
  passwordRequired: true,
  selfRegistrationAllowed: false,
  secondFactor: "AUTHENTICATOR_OR_OTP",
  recovery: ["SMS_OTP", "RECOVERY_CODES"],
};

