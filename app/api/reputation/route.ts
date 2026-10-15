import { NextRequest, NextResponse } from "next/server";
import { corporateAuthorization, stagingRest } from "@/lib/hq-server";

export async function GET(request: NextRequest) {
  const authorization = await corporateAuthorization().catch(() => null);
  if (!authorization) return NextResponse.json({ error: "Não autenticado." }, { status: 401 });
  const platform = request.nextUrl.searchParams.get("platform") || undefined;
  try {
    const [reviews, ratings, restaurants, orders, profiles] = await Promise.all([
      stagingRest("reviews?select=*&order=created_at.desc&limit=500"),
      stagingRest("ratings?select=*&order=created_at.desc&limit=500"),
      stagingRest("restaurants?select=id,name,rating&limit=500"),
      stagingRest("orders?select=id,restaurant_id,courier_id,created_at&limit=500"),
      stagingRest("profiles?select=id,full_name,role&limit=1000"),
    ]);
    const rows = Array.isArray(ratings) ? ratings : [];
    const visibleReviews = Array.isArray(reviews) ? reviews : [];
    const average = rows.length ? rows.reduce((sum, item) => sum + Number(item.restaurant_food_rating || item.restaurant_service_rating || item.rating || 0), 0) / rows.length : 0;
    return NextResponse.json({ data: { reviews: visibleReviews, ratings: rows, restaurants, orders, profiles, platform: platform || "all", metrics: { total: rows.length + visibleReviews.length, average: Number(average.toFixed(2)), negative: rows.filter(item => Number(item.restaurant_food_rating || item.rating || 0) <= 2).length, unanswered: 0, reports: 0 } } }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    console.error("REPUTATION_LOAD_FAILED", String(error));
    return NextResponse.json({ error: "Não foi possível carregar Avaliações & Reputação." }, { status: 503 });
  }
}
