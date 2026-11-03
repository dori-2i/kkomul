import { getSupabase } from "./supabase";

export const CATEGORY_LABEL: Record<string, string> = {
  bodysuit: "바디슈트",
  romper: "우주복",
  set: "상하복",
  top: "상의",
  outer: "아우터",
  legwear: "하의·양말",
  acc: "모자·소품",
  toy: "장난감",
};

type PriceRow = { mall_name: string; price: number; link: string; collected_at: string };

type ProductRow = {
  id: number;
  sku: string;
  name: string;
  category: string;
  list_price: number | null;
  image_url: string | null;
  brands: { name: string; images_allowed: boolean } | null;
  product_prices: PriceRow[];
};

export type ProductCard = {
  id: number;
  name: string;
  brand: string | null;
  category: string;
  imageUrl: string | null; // 이미지 사용을 허락받은 브랜드만 값이 있음
  listPrice: number | null;
  lowest: PriceRow | null;
  mallCount: number;
  discountRate: number | null;
};

// 판매처마다 가장 최근 가격만 남긴 뒤, 그중 최저가를 고름
function summarize(p: ProductRow): ProductCard {
  const latestByMall = new Map<string, PriceRow>();
  for (const row of p.product_prices ?? []) {
    const prev = latestByMall.get(row.mall_name);
    if (!prev || row.collected_at > prev.collected_at) latestByMall.set(row.mall_name, row);
  }
  const prices = [...latestByMall.values()].sort((a, b) => a.price - b.price);
  const lowest = prices[0] ?? null;
  const discountRate =
    lowest && p.list_price && p.list_price > lowest.price
      ? Math.round((1 - lowest.price / p.list_price) * 100)
      : null;

  return {
    id: p.id,
    name: p.name,
    brand: p.brands?.name ?? null,
    category: p.category,
    imageUrl: p.brands?.images_allowed ? p.image_url : null,
    listPrice: p.list_price,
    lowest,
    mallCount: prices.length,
    discountRate,
  };
}

export type ProductDetail = ProductCard & {
  sizes: string[];
  prices: PriceRow[]; // 판매처별 최근 가격, 싼 순서
};

export async function getProduct(id: number): Promise<ProductDetail | null> {
  const { data, error } = await getSupabase()
    .from("products")
    .select(
      "id, sku, name, category, list_price, image_url, brands(name, images_allowed), product_prices(mall_name, price, link, collected_at), product_sizes(size_label)",
    )
    .eq("id", id)
    .maybeSingle();

  if (error) throw new Error(`상품을 불러오지 못했어요: ${error.message}`);
  if (!data) return null;

  const row = data as unknown as ProductRow & { product_sizes: { size_label: string }[] };
  const card = summarize(row);
  const latestByMall = new Map<string, PriceRow>();
  for (const pr of row.product_prices ?? []) {
    const prev = latestByMall.get(pr.mall_name);
    if (!prev || pr.collected_at > prev.collected_at) latestByMall.set(pr.mall_name, pr);
  }
  return {
    ...card,
    sizes: (row.product_sizes ?? []).map((s) => s.size_label),
    prices: [...latestByMall.values()].sort((a, b) => a.price - b.price),
  };
}

export type SizeFitRow = {
  size_label: string;
  in_stock: boolean;
  height_min_cm: number | null;
  height_max_cm: number | null;
  month_min: number | null;
  month_max: number | null;
  verdict: "작아요" | "딱 맞아요" | "넉넉해요" | "아직 너무 커요" | null;
  basis: "brand_range" | "max_only" | null;
  brand_recommended: boolean;
};

// DB의 product_size_fit 함수로 사이즈별 판정을 받아 옴 (판정 규칙은 DB 한 곳에서 관리)
export async function getSizeFit(productId: number, month: number, height: number): Promise<SizeFitRow[]> {
  const { data, error } = await getSupabase().rpc("product_size_fit", {
    p_product: productId,
    p_month: month,
    p_height: height,
  });
  if (error) throw new Error(`사이즈 판정을 불러오지 못했어요: ${error.message}`);
  return (data ?? []) as SizeFitRow[];
}

export async function getProducts(): Promise<ProductCard[]> {
  const { data, error } = await getSupabase()
    .from("products")
    .select(
      "id, sku, name, category, list_price, image_url, brands(name, images_allowed), product_prices(mall_name, price, link, collected_at)",
    )
    .order("id");

  if (error) throw new Error(`상품을 불러오지 못했어요: ${error.message}`);
  return (data as unknown as ProductRow[]).map(summarize);
}
