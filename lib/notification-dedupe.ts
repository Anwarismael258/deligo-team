type Notification=Record<string,unknown>;
export function dedupeNotifications<T extends Notification>(rows:T[]):T[]{
 const seen=new Set<string>();
 return rows.filter(row=>{
  // Old task routes emitted a second notification beside the database trigger.
  if(row.source_type==="task"&&!row.dedupe_key&&rows.some(peer=>peer!==row&&peer.dedupe_key&&peer.source_type==="task"&&peer.source_id===row.source_id&&peer.body===row.body&&Math.abs(Date.parse(String(peer.created_at))-Date.parse(String(row.created_at)))<60000))return false;
  const event=String(row.target_url||"").match(/[?&]central_event_id=([^&]+)/)?.[1];
  const key=row.dedupe_key?`key:${row.employee_id}:${row.dedupe_key}`:event?`mestre24:${row.employee_id}:${event}`:`id:${row.id}`;
  if(seen.has(key))return false;seen.add(key);return true;
 });
}
