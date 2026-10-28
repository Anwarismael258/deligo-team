export type KycRow = Record<string, any>;
export const sarcaDocumentNames: Record<string, string> = {
  bi_front: "BI frente", bi_back: "BI verso", selfie: "Selfie",
  driver_license: "Carta de conducao", vehicle_registration: "Livrete",
  vehicle_front: "Foto do carro frente", vehicle_back: "Foto do carro traseira",
  vehicle_side: "Foto do carro lateral", vehicle_interior: "Foto do carro interior",
  vehicle_with_driver: "Foto do carro com motorista",
};
export type KycDocument = { id: string; caseId: string; label: string; url: string | null; status: string };
export type KycGroup = { id: string; name: string; platform: string; status: string; rows: KycRow[]; documents: KycDocument[] };

export function documentsForCase(row: KycRow): KycDocument[] {
  const type = String(row.document_type || row.source_snapshot?.document_type || row.subject_name || "");
  const references = Array.isArray(row.document_references) && row.document_references.length
    ? row.document_references : [{ signed_url: row.file_path || row.storage_path || row.document_url }];
  const seen = new Set<string>();
  return references.flatMap((reference: any, index: number) => {
    const item = typeof reference === "string" ? { signed_url: reference } : reference || {};
    const path = String(item.signed_url || item.url || "");
    const url = /^https?:\/\//i.test(path) ? path : null;
    const key = url || `${row.id}:${index}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [{ id: `${row.id}:${index}`, caseId: String(row.id), label: sarcaDocumentNames[type] || String(item.label || row.document_label || type || `Documento ${index + 1}`), url, status: String(row.status || "submitted") }];
  });
}

export function groupKycCases(rows: KycRow[]): KycGroup[] {
  const groups = new Map<string, KycGroup>();
  for (const row of rows) {
    const platform = String(row.platform_name || row.platforms?.name || row._platform || "Plataforma");
    const subject = row.subject_user_id || row.user_id || row.profile_id || row.entity_reference || row.id;
    const id = `${platform.toLowerCase()}:${subject}`;
    let group = groups.get(id);
    if (!group) {
      group = { id, name: String(row.applicant_name || row.full_name || row.name || "Utilizador"), platform, status: "submitted", rows: [], documents: [] };
      groups.set(id, group);
    }
    if (group.rows.some(existing => existing.id === row.id)) continue;
    group.rows.push(row);
    group.documents.push(...documentsForCase(row));
  }
  for (const group of groups.values()) {
    const states = group.rows.map(row => String(row.status || "submitted"));
    group.status = states.every(status => status === "approved") ? "approved"
      : ["suspended", "rejected", "correction_requested"].find(status => states.includes(status)) || "submitted";
    const order = Object.keys(sarcaDocumentNames);
    group.documents.sort((a, b) => {
      const rank = (label: string) => { const index = order.findIndex(type => sarcaDocumentNames[type] === label); return index < 0 ? 100 : index; };
      return rank(a.label) - rank(b.label);
    });
  }
  return [...groups.values()];
}
