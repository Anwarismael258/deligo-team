export const sensitiveDataClasses = {
  public: ["platform.public_catalog"],
  internal: ["operations.tasks", "marketing.calendar"],
  confidential: ["employees.profile", "contracts.metadata"],
  personal: ["employees.documents", "customers.identity"],
  financial: ["payments.ledger", "payroll", "bank_accounts"],
  legal: ["corporate_documents", "shareholder_resolutions"],
  restricted: ["secrets", "security_configuration", "ownership_changes"],
} as const;

export const separationOfDuties = [
  ["procurement.request.create", "procurement.payment.execute"],
  ["finance.result.prepare", "profit_distribution.approve"],
  ["finance.expense.create", "payment.execute"],
  ["finance.transactions.approve", "payment.reconcile"],
  ["payment.execute", "payment.reconcile"],
  ["hr.employee.create", "security.super_admin.assign"],
  ["technology.integrations.manage", "finance.transactions.approve"],
] as const;

export function conflicts(permissions: readonly string[]) {
  const permissionSet = new Set(permissions);
  return separationOfDuties.filter(([left, right]) => permissionSet.has(left) && permissionSet.has(right));
}
