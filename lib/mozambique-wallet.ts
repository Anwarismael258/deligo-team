export type MozambiqueWalletMethod = "mpesa" | "emola" | "mkesh";

export type DetectedWalletOperator = {
  method: MozambiqueWalletMethod;
  provider: "vodacom_mpesa" | "movitel" | "tmcel_mkesh";
  label: "M-Pesa / Vodacom" | "e-Mola / Movitel" | "mKesh / Tmcel";
  phone: string;
};

export function normalizeMozambiqueMsisdn(value: string) {
  let digits = String(value || "").replace(/\D/g, "");
  if (digits.startsWith("258")) digits = digits.slice(3);
  if (digits.length === 10 && digits.startsWith("0")) digits = digits.slice(1);
  return digits;
}

export function detectMozambiqueWalletOperator(value: string): DetectedWalletOperator {
  const phone = normalizeMozambiqueMsisdn(value);
  if (!/^8[2-7]\d{7}$/.test(phone)) throw new Error("Número PaySuite inválido.");
  if (/^8[23]/.test(phone)) return { phone, method: "mkesh", provider: "tmcel_mkesh", label: "mKesh / Tmcel" };
  if (/^8[45]/.test(phone)) return { phone, method: "mpesa", provider: "vodacom_mpesa", label: "M-Pesa / Vodacom" };
  return { phone, method: "emola", provider: "movitel", label: "e-Mola / Movitel" };
}
