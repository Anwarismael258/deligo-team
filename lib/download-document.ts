export async function downloadDocument(url: string, filename: string) {
  const response = await fetch(url, { credentials: "omit", signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error("Não foi possível descarregar. Abra novamente o documento para renovar o acesso.");
  const blob = await response.blob();
  const extension: Record<string, string> = { "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "application/pdf": ".pdf" };
  const objectUrl = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = objectUrl;
  anchor.download = filename + (extension[blob.type] || "");
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
}
