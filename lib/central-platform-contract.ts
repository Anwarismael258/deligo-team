export const corporatePlatforms = {
  deligo: { code: "DELIGO", name: "DeliGo", integration: "connected" },
  sarca: { code: "SARCA", name: "SARCA", integration: "connected" },
  taomoz: { code: "DELIGO_MARKETING", name: "DeliGo Market", integration: "connected" },
  comunhao: { code: "COMUNHAO", name: "Comunhão", integration: "connected" },
  mestre24: { code: "MESTRE24", name: "Mestre24", integration: "connected" },
  exploremoz: { code: "EXPLOREMOZ", name: "ExploreMoz", integration: "planned" },
} as const;

export type CorporatePlatformSlug = keyof typeof corporatePlatforms;
export type CorporatePlatformCode = (typeof corporatePlatforms)[CorporatePlatformSlug]["code"];

export type CentralOperationalEvent = {
  platform: CorporatePlatformSlug;
  sourceApp: string;
  sourceEventId?: string;
  eventType: string;
  entityType: string;
  entityId: string;
  userId?: string;
  actorUserId?: string;
  payload?: Record<string, unknown>;
  occurredAt?: string;
};

export type CentralFinancialEvent = {
  platform: CorporatePlatformSlug;
  sourceApp: string;
  sourceRecordId?: string;
  transactionType: string;
  grossAmount: number;
  paymentStatus: "pending" | "authorized" | "confirmed" | "failed" | "refunded" | "reversed" | "cancelled";
  entityType?: string;
  entityId?: string;
  userId?: string;
  platformFee?: number;
  providerFee?: number;
  partnerAmount?: number;
  currency?: string;
  paymentMethod?: string;
  reference?: string;
  metadata?: Record<string, unknown>;
  occurredAt?: string;
};

export function isCorporatePlatform(value: string): value is CorporatePlatformSlug {
  return value in corporatePlatforms;
}

export function platformCode(platform: CorporatePlatformSlug): CorporatePlatformCode {
  return corporatePlatforms[platform].code;
}
