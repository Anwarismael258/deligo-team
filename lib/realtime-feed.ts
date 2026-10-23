export type RealtimeEvent = {
  id: number;
  topic: string;
  resource_type: string | null;
  resource_id: string | null;
  event_type: string;
  workflow_case_id: string | null;
  platform_id: string | null;
  department_id: string | null;
  created_at: string;
};

export type RealtimeFeedResponse = {
  events: RealtimeEvent[];
  cursor: number;
  checkedAt: string;
  degraded?: boolean;
};

export function dedupeRealtimeEvents(events: RealtimeEvent[], seen = new Set<number>()) {
  return events.filter((event) => {
    if (seen.has(event.id)) return false;
    seen.add(event.id);
    return true;
  });
}

export function nextRealtimeCursor(current: number, events: RealtimeEvent[]) {
  return events.reduce((cursor, event) => Math.max(cursor, event.id), current);
}
