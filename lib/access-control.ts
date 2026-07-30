import type { PlatformSlug } from "./contracts";
import type { CorporateIdentity, Department } from "./identity";
import { conflicts } from "./security-policy";

export type PermissionGrant = {
  permission: string;
  department: Department | "*";
  platforms: Array<PlatformSlug | "*">;
  legalEntityId: string;
  validUntil: string | null;
};

export type AccessRequest = {
  permission: string;
  department: Department;
  platform?: PlatformSlug;
  legalEntityId: string;
  now: string;
};

export type AccessDecision =
  | { allowed: true; grant: PermissionGrant }
  | { allowed: false; reason: "IDENTITY_INACTIVE" | "OUTSIDE_VALIDITY" | "SCOPE_MISMATCH" | "PERMISSION_CONFLICT" };

export function authorize(identity: CorporateIdentity, grants: readonly PermissionGrant[], request: AccessRequest): AccessDecision {
  if (identity.status !== "ACTIVE") return { allowed: false, reason: "IDENTITY_INACTIVE" };
  if (identity.validUntil && identity.validUntil < request.now) return { allowed: false, reason: "OUTSIDE_VALIDITY" };

  const grant = grants.find((candidate) =>
    candidate.permission === request.permission &&
    candidate.legalEntityId === request.legalEntityId &&
    (candidate.department === "*" || candidate.department === request.department) &&
    (!request.platform || candidate.platforms.includes("*") || candidate.platforms.includes(request.platform)) &&
    (!candidate.validUntil || candidate.validUntil >= request.now),
  );

  if (!grant) return { allowed: false, reason: "SCOPE_MISMATCH" };
  const effectivePermissions = grants.map(({ permission }) => permission);
  if (conflicts(effectivePermissions).some(([left, right]) => left === request.permission || right === request.permission)) {
    return { allowed: false, reason: "PERMISSION_CONFLICT" };
  }
  return { allowed: true, grant };
}
