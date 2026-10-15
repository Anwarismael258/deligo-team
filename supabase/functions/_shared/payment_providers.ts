export type MobileMoneyMethod = "mpesa" | "emola";
export type PaymentRail = MobileMoneyMethod | "movitel";

export type DebitoPayConfig = {
  baseUrl: string;
  token: string;
  walletIds: Record<MobileMoneyMethod, string>;
  callbackUrl: string;
  webhookSecret: string;
};

function env(name: string): string {
  return Deno.env.get(name)?.trim() || "";
}

function firstEnv(names: string[]): string {
  for (const name of names) {
    const value = env(name);
    if (value) return value;
  }
  return "";
}

function normalizeBaseUrl(value: string): string {
  return value.replace(/\/$/, "");
}

export function getDebitoPayConfig(): DebitoPayConfig {
  return {
    baseUrl: normalizeBaseUrl(firstEnv([
      "DEBITO_PAY_BASE_URL",
      "DEBITOPAY_API_URL",
    ])),
    token: firstEnv([
      "DEBITO_PAY_SECRET_KEY",
      "DEBITOPAY_API_KEY",
      "DEBITOPAY_TOKEN",
      "DEBITO_PAY_TOKEN",
    ]),
    walletIds: {
      mpesa: firstEnv([
        "DEBITO_PAY_MPESA_WALLET_ID",
        "DEBITO_PAY_WALLET_ID",
        "DEBITOPAY_WALLET_ID",
      ]),
      emola: firstEnv([
        "DEBITO_PAY_EMOLA_WALLET_ID",
        "DEBITO_PAY_WALLET_ID",
        "DEBITOPAY_WALLET_ID",
      ]),
    },
    callbackUrl: env("DEBITO_PAY_CALLBACK_URL"),
    webhookSecret: firstEnv([
      "DEBITO_PAY_WEBHOOK_SECRET",
      "WEBHOOK_SECRET",
    ]),
  };
}

export function getDebitoPayWalletId(
  config: DebitoPayConfig,
  method: MobileMoneyMethod,
): string {
  return config.walletIds[method] || "";
}

export function buildDebitoPayUrl(
  config: DebitoPayConfig,
  path: string,
): string {
  return `${config.baseUrl}${path.startsWith("/") ? path : `/${path}`}`;
}

export function getRailProvider(rail: PaymentRail): "debito_pay" | "mpesa" | "movitel" {
  switch (rail) {
    case "mpesa":
    case "emola":
      return "debito_pay";
    case "movitel":
      return "movitel";
  }
}

