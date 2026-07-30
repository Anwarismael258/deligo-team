import type { EmployeeId } from "./identity";

export type Shareholder = {
  employeeId: EmployeeId;
  displayName: string;
  quotaPercent: 50;
  corporateTitle: string;
  isManagingPartner: boolean;
  isSuperAdministrator: boolean;
};

export type ReservedMatter =
  | "PROFIT_DISTRIBUTION"
  | "SHARE_CAPITAL_CHANGE"
  | "OWNERSHIP_CHANGE"
  | "MANAGING_PARTNER_APPOINTMENT"
  | "MATERIAL_DEBT"
  | "MATERIAL_ASSET_DISPOSAL"
  | "COMPANY_DISSOLUTION";

export const deligoTriunfalGovernance = {
  legalEntityId: "DELIGO-TRIUNFAL-LDA",
  legalName: "DeliGo Triunfal, Lda.",
  legalForm: "SOCIEDADE_POR_QUOTAS",
  totalOwnershipPercent: 100,
  shareholders: [
    {
      employeeId: "DG-0001",
      displayName: "Anwar Abubacar Ismael",
      quotaPercent: 50,
      corporateTitle: "CEO e Fundador",
      isManagingPartner: true,
      isSuperAdministrator: true,
    },
    {
      employeeId: "DG-0002",
      displayName: "Sara Vitorino Feniosse Ismael",
      quotaPercent: 50,
      corporateTitle: "Sócia e Diretora Financeira",
      isManagingPartner: false,
      isSuperAdministrator: false,
    },
  ] satisfies Shareholder[],
  reservedMatters: [
    "PROFIT_DISTRIBUTION", "SHARE_CAPITAL_CHANGE", "OWNERSHIP_CHANGE",
    "MANAGING_PARTNER_APPOINTMENT", "MATERIAL_DEBT", "MATERIAL_ASSET_DISPOSAL",
    "COMPANY_DISSOLUTION",
  ] satisfies ReservedMatter[],
  reservedMatterApprovalsRequired: 2,
} as const;

export const financeDirectorPermissions = [
  "finance.view", "finance.budget.create", "finance.expense.create",
  "finance.transactions.review", "finance.transactions.approve", "accounting.view",
  "treasury.view", "bank_accounts.view", "payables.view", "reports.view",
  "approvals.finance", "profit_distribution.review", "reserved_matters.approve",
] as const;

export const founderPermissions = [
  "security.super_admin", "security.permissions.manage", "governance.manage",
  "ownership.view", "reserved_matters.approve",
] as const;

export type ApprovalActor = { employeeId: EmployeeId; permissions: readonly string[] };

export function canApproveReservedMatter(matter: ReservedMatter, actors: readonly ApprovalActor[]) {
  if (!deligoTriunfalGovernance.reservedMatters.includes(matter)) return false;
  const shareholderIds = new Set(deligoTriunfalGovernance.shareholders.map(({ employeeId }) => employeeId));
  const validApprovers = new Set(actors
    .filter(({ employeeId, permissions }) => shareholderIds.has(employeeId) && permissions.includes("reserved_matters.approve"))
    .map(({ employeeId }) => employeeId));
  return validApprovers.size === deligoTriunfalGovernance.reservedMatterApprovalsRequired;
}
