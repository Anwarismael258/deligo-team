"use client";
import { LegalArchive } from "../../components/LegalArchive";

export default function LegalManagement() {
  return <main className="financePanel" style={{ maxWidth: 1150, margin: "40px auto", padding: 24 }}><span>JURÍDICO · GOVERNAÇÃO LEGAL</span><h1>Gestão jurídica corporativa</h1><p>Contratos, documentos, prazos e casos da DeliGo Triunfal e das suas plataformas.</p><LegalArchive/><div className="safeNotice"><b>Arquivo protegido</b><span>Classificação, versões, hash, uploader, histórico de acesso e auditoria devem permanecer associados ao documento original.</span></div></main>;
}
