import { NextRequest, NextResponse } from "next/server";
import { supabaseUrl } from "@/lib/hq-server";

const platformIds: Record<string, string> = {
  deligo: "20000000-0000-0000-0000-000000000001",
  comunhao: "20000000-0000-0000-0000-000000000002",
  taomoz: "20000000-0000-0000-0000-000000000003",
  sarca: "20000000-0000-0000-0000-000000000004",
  mestre24: "20000000-0000-0000-0000-000000000005",
};
const categories = new Set(["kyc", "support", "dispute", "delivery_proof", "trip_proof", "logistics", "merchant", "church", "marketplace", "marketing", "legal", "finance", "operational", "other"]);
const classifications = new Set(["operational", "confidential", "restricted"]);

type FileRegistration = {
  platform?: string;
  source_system?: string;
  source_bucket?: string;
  source_path?: string;
  subject_type?: string;
  subject_id?: string;
  category?: string;
  classification?: string;
  file_name?: string;
  mime_type?: string | null;
  size_bytes?: number | null;
  checksum_sha256?: string | null;
  uploaded_at?: string | null;
  metadata?: Record<string, unknown>;
};

export async function POST(request: NextRequest) {
  const expectedToken = process.env.HQ_FILE_REGISTRY_TOKEN?.trim();
  const receivedToken = request.headers.get("x-hq-file-registry-token")?.trim();
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!expectedToken || !serviceKey || receivedToken !== expectedToken) return NextResponse.json({ error: "Integração não autorizada." }, { status: 401 });

  const body = await request.json() as FileRegistration;
  const platformId = platformIds[String(body.platform || "")];
  const sourceSystem = String(body.source_system || body.platform || "");
  if (!platformId || !["deligo", "comunhao", "sarca", "taomoz", "hq"].includes(sourceSystem) || !body.source_bucket || !body.source_path || !body.subject_type || !body.subject_id || !body.file_name || !categories.has(String(body.category)) || !classifications.has(String(body.classification))) {
    return NextResponse.json({ error: "Registo de ficheiro inválido." }, { status: 400 });
  }
  if (/^https?:\/\//i.test(body.source_path)) return NextResponse.json({ error: "O catálogo aceita caminho de storage, não URL." }, { status: 400 });

  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/register_central_file_v1`, {
    method: "POST",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json", Accept: "application/json", "Content-Profile": "hq" },
    body: JSON.stringify({
      p_platform_id: platformId,
      p_source_system: sourceSystem,
      p_source_bucket: body.source_bucket,
      p_source_path: body.source_path,
      p_subject_type: body.subject_type,
      p_subject_id: body.subject_id,
      p_category: body.category,
      p_classification: body.classification,
      p_file_name: body.file_name,
      p_mime_type: body.mime_type || null,
      p_size_bytes: body.size_bytes || null,
      p_checksum_sha256: body.checksum_sha256 || null,
      p_uploaded_at: body.uploaded_at || null,
      p_metadata: body.metadata || {},
    }),
    cache: "no-store",
  });
  if (!response.ok) return NextResponse.json({ error: "A Central não conseguiu registar o ficheiro." }, { status: 502 });
  return NextResponse.json({ record: await response.json() }, { status: 201 });
}
