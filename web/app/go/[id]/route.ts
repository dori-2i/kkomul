import { NextResponse, type NextRequest } from "next/server";
import { getSupabase } from "@/lib/supabase";

// "보러 가기" → /go/상품번호?mall=판매처&from=화면
// 클릭을 기록(record_click)하고 DB에 저장된 판매처 링크로 이동시킴
const SESSION_COOKIE = "kk_sid";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET(req: NextRequest, ctx: RouteContext<"/go/[id]">) {
  const { id } = await ctx.params;
  const productId = Number(id);
  const mall = req.nextUrl.searchParams.get("mall") ?? "";
  const from = req.nextUrl.searchParams.get("from") ?? "product";

  if (!Number.isInteger(productId) || productId <= 0 || !mall) {
    return NextResponse.redirect(new URL("/", req.url));
  }

  // 방문자 구분용 임의 번호 (개인정보 아님). 없으면 새로 만들어 1년간 보관
  const saved = req.cookies.get(SESSION_COOKIE)?.value;
  const sessionId = saved && UUID_RE.test(saved) ? saved : crypto.randomUUID();

  let target: URL = new URL(`/products/${productId}`, req.url);
  try {
    const { data, error } = await getSupabase().rpc("record_click", {
      p_product: productId,
      p_mall: mall,
      p_source: from,
      p_session: sessionId,
    });
    if (!error && typeof data === "string" && /^https?:\/\//.test(data)) target = new URL(data);
  } catch {
    // 기록에 실패해도 사용자는 상품 화면으로 돌아가게 함
  }

  const res = NextResponse.redirect(target, 302);
  if (sessionId !== saved) {
    res.cookies.set(SESSION_COOKIE, sessionId, {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      maxAge: 60 * 60 * 24 * 365,
      path: "/",
    });
  }
  return res;
}
