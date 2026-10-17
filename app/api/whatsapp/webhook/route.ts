
import { createHmac, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

function isValidVerifyToken(token: string | null): boolean {
  const expected = process.env.WHATSAPP_VERIFY_TOKEN;

  return Boolean(
    token &&
      expected &&
      token.length === expected.length &&
      timingSafeEqual(Buffer.from(token), Buffer.from(expected))
  );
}

// Meta uses this endpoint to verify the webhook URL.
export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;

  const mode = params.get("hub.mode");
  const token = params.get("hub.verify_token");
  const challenge = params.get("hub.challenge");

  if (
    mode === "subscribe" &&
    isValidVerifyToken(token) &&
    challenge !== null
  ) {
    return new NextResponse(challenge, {
      status: 200,
      headers: { "Content-Type": "text/plain" },
    });
  }

  return NextResponse.json(
    { error: "Webhook verification failed" },
    { status: 403 }
  );
}

// Meta sends webhook events to this endpoint.
export async function POST(request: NextRequest) {
  const appSecret = process.env.META_APP_SECRET;
  const signature = request.headers.get("x-hub-signature-256");

  if (!appSecret || !signature?.startsWith("sha256=")) {
    return NextResponse.json(
      { error: "Webhook signature missing or configuration incomplete" },
      { status: 401 }
    );
  }

  const rawBody = await request.text();
  const receivedHex = signature.slice("sha256=".length);

  const expectedHex = createHmac("sha256", appSecret)
    .update(rawBody)
    .digest("hex");

  const received = Buffer.from(receivedHex, "hex");
  const expected = Buffer.from(expectedHex, "hex");

  if (
    receivedHex.length !== 64 ||
    received.length !== expected.length ||
    !timingSafeEqual(received, expected)
  ) {
    return NextResponse.json(
      { error: "Invalid webhook signature" },
      { status: 401 }
    );
  }

  let event: unknown;

  try {
    event = JSON.parse(rawBody);
  } catch {
    return NextResponse.json(
      { error: "Invalid JSON payload" },
      { status: 400 }
    );
  }

  // The signature is verified. Message processing will be added next.
  console.info("WhatsApp webhook event received", {
    object:
      typeof event === "object" && event !== null && "object" in event
        ? event.object
        : undefined,
  });

  return NextResponse.json({ received: true }, { status: 200 });
}
