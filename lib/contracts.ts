export type PlatformSlug = "deligo" | "comunhao" | "sarca" | "taomoz";

export type ConnectionState = {
  connected: false;
  source: PlatformSlug;
  checkedAt: null;
  reason: "BACKEND_FROZEN";
};

export type EmployeeContext = {
  id: string;
  name: string;
  roles: string[];
  platforms: PlatformSlug[];
  permissions: string[];
};

export type PlatformMetric = {
  key: string;
  label: string;
  value: number | null;
  currency?: "MZN";
  source: PlatformSlug;
};

export type SupportCase = {
  id: string;
  platform: PlatformSlug;
  subject: string;
  status: "new" | "assigned" | "in_progress" | "waiting" | "resolved" | "closed";
  priority: "low" | "normal" | "high" | "urgent";
};

export type MarketingCampaign = {
  id: string;
  platforms: PlatformSlug[];
  title: string;
  status: "draft" | "review" | "approved" | "published" | "archived";
};

export type FieldVisit = {
  id: string;
  platform: PlatformSlug;
  workerId: string;
  status: "planned" | "in_progress" | "completed" | "cancelled";
};
