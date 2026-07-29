import type {
  ConnectionState,
  FieldVisit,
  MarketingCampaign,
  PlatformMetric,
  PlatformSlug,
  SupportCase,
} from "./contracts";

export interface PlatformAdapter {
  readonly platform: PlatformSlug;
  connection(): Promise<ConnectionState>;
  metrics(): Promise<PlatformMetric[]>;
  supportCases(): Promise<SupportCase[]>;
  campaigns(): Promise<MarketingCampaign[]>;
  fieldVisits(): Promise<FieldVisit[]>;
}

class FrozenAdapter implements PlatformAdapter {
  constructor(readonly platform: PlatformSlug) {}

  async connection(): Promise<ConnectionState> {
    return { connected: false, source: this.platform, checkedAt: null, reason: "BACKEND_FROZEN" };
  }

  async metrics(): Promise<PlatformMetric[]> { return []; }
  async supportCases(): Promise<SupportCase[]> { return []; }
  async campaigns(): Promise<MarketingCampaign[]> { return []; }
  async fieldVisits(): Promise<FieldVisit[]> { return []; }
}

export const adapters: Record<PlatformSlug, PlatformAdapter> = {
  deligo: new FrozenAdapter("deligo"),
  comunhao: new FrozenAdapter("comunhao"),
  sarca: new FrozenAdapter("sarca"),
  taomoz: new FrozenAdapter("taomoz"),
};
