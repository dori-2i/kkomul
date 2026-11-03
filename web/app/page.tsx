import Link from "next/link";
import { Suspense } from "react";
import { CATEGORY_LABEL, getProducts, type ProductCard } from "@/lib/products";
import { kstMonthDay, won } from "@/lib/format";
import ProductThumb from "./ProductThumb";

export default function Home() {
  return (
    <div className="mx-auto flex w-full max-w-md flex-1 flex-col bg-[#FAF7FD]">
      <header className="sticky top-0 z-10 bg-white px-5 py-4 shadow-sm">
        <h1 className="text-2xl font-black tracking-tight text-[#7B4BC4]">꼬물샵</h1>
        <p className="mt-1 text-sm text-gray-600">우리 아기 사이즈에 맞는 옷, 참고 가격과 함께</p>
      </header>

      <main className="flex flex-1 flex-col gap-3 px-4 py-5">
        <div className="flex items-baseline justify-between">
          <h2 className="text-lg font-bold text-gray-900">상품 목록</h2>
          <span className="text-xs text-gray-600">판매처별 최근 확인 가격 기준</span>
        </div>

        <Suspense fallback={<p className="py-10 text-center text-sm text-gray-600">상품을 불러오는 중…</p>}>
          <ProductList />
        </Suspense>
      </main>
    </div>
  );
}

async function ProductList() {
  let products: ProductCard[];
  try {
    products = await getProducts();
  } catch (e) {
    return (
      <p className="rounded-xl bg-red-50 p-4 text-sm text-red-800">
        {e instanceof Error ? e.message : "상품을 불러오지 못했어요."}
      </p>
    );
  }

  if (products.length === 0) {
    return <p className="py-10 text-center text-sm text-gray-600">아직 등록된 상품이 없어요.</p>;
  }

  return (
    <ul className="flex flex-col gap-3">
      {products.map((p) => (
        <li key={p.id}>
          <ProductItem p={p} />
        </li>
      ))}
    </ul>
  );
}

function ProductItem({ p }: { p: ProductCard }) {
  return (
    <article className="flex gap-4 rounded-2xl bg-white p-4 shadow-sm">
      <Link href={`/products/${p.id}`} aria-label={`${p.name} 상세 보기`} className="flex-none">
        <ProductThumb src={p.imageUrl} alt={p.name} />
      </Link>

      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <div className="flex items-center gap-2 text-xs text-gray-600">
          {p.brand && <span className="font-semibold text-gray-800">{p.brand}</span>}
          <span>{CATEGORY_LABEL[p.category] ?? p.category}</span>
        </div>
        <h3 className="line-clamp-2 text-sm font-medium leading-snug text-gray-900">
          <Link href={`/products/${p.id}`} className="hover:underline">
            {p.name}
          </Link>
        </h3>

        {p.lowest ? (
          <>
            <div className="flex items-baseline gap-1.5">
              {p.discountRate !== null && (
                <span className="text-base font-black text-red-700">{p.discountRate}%</span>
              )}
              <span className="text-lg font-bold text-gray-900">{won(p.lowest.price)}원</span>
              {p.discountRate !== null && p.listPrice && (
                <span className="text-xs text-gray-500 line-through">{won(p.listPrice)}</span>
              )}
            </div>
            <div className="mt-auto flex items-center justify-between gap-2">
              <span className="text-xs text-gray-600">
                {p.lowest.mall_name} · 가격 확인일 {kstMonthDay(p.lowest.collected_at)}
                {p.mallCount > 1 && ` · ${p.mallCount}곳 비교`}
              </span>
              <Link
                href={`/products/${p.id}`}
                className="flex-none rounded-full bg-[#7B4BC4] px-3 py-2 text-xs font-bold text-white"
              >
                사이즈 보기
              </Link>
            </div>
          </>
        ) : (
          <span className="text-xs text-gray-600">가격 정보 준비 중</span>
        )}
      </div>
    </article>
  );
}
