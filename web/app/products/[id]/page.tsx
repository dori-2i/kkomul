import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CATEGORY_LABEL, getProduct } from "@/lib/products";
import { kstMonthDay, won } from "@/lib/format";
import ProductThumb from "../../ProductThumb";
import SizeFit from "./SizeFit";

export default function ProductPage({ params }: PageProps<"/products/[id]">) {
  return (
    <div className="mx-auto flex w-full max-w-md flex-1 flex-col bg-[#FAF7FD]">
      <header className="sticky top-0 z-10 flex items-center gap-1 bg-white px-2 py-2 shadow-sm">
        <Link href="/" aria-label="목록으로" className="flex h-11 w-11 items-center justify-center text-gray-900">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="m15 5-7 7 7 7" />
          </svg>
        </Link>
        <span className="text-base font-bold text-gray-900">상품 상세</span>
      </header>

      <Suspense fallback={<p className="py-10 text-center text-sm text-gray-600">상품을 불러오는 중…</p>}>
        <ProductDetail params={params} />
      </Suspense>
    </div>
  );
}

async function ProductDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const productId = Number(id);
  if (!Number.isInteger(productId) || productId <= 0) notFound();

  const p = await getProduct(productId);
  if (!p) notFound();

  return (
    <main className="flex flex-1 flex-col gap-4 px-4 py-5">
      <ProductThumb src={p.imageUrl} alt={p.name} size="lg" />

      <section className="flex flex-col gap-1">
        <div className="flex items-center gap-2 text-sm text-gray-600">
          {p.brand && <span className="font-semibold text-gray-800">{p.brand}</span>}
          <span>{CATEGORY_LABEL[p.category] ?? p.category}</span>
        </div>
        <h1 className="text-xl font-bold leading-snug text-gray-900">{p.name}</h1>
        {p.lowest && (
          <div className="mt-1 flex items-baseline gap-2">
            {p.discountRate !== null && <span className="text-lg font-black text-red-700">{p.discountRate}%</span>}
            <span className="text-2xl font-bold text-gray-900">{won(p.lowest.price)}원</span>
            {p.discountRate !== null && p.listPrice && (
              <span className="text-sm text-gray-500 line-through">{won(p.listPrice)}</span>
            )}
          </div>
        )}
      </section>

      <SizeFit productId={p.id} hasSizes={p.sizes.length > 0} />

      <section className="flex flex-col gap-2 rounded-2xl bg-white p-4 shadow-sm">
        <h2 className="text-base font-bold text-gray-900">판매처별 가격</h2>
        {p.prices.length === 0 ? (
          <p className="text-sm text-gray-600">가격 정보 준비 중이에요.</p>
        ) : (
          <ul className="flex flex-col divide-y divide-gray-100">
            {p.prices.map((pr, i) => (
              <li key={pr.mall_name} className="flex items-center justify-between gap-3 py-3">
                <div className="flex min-w-0 flex-col">
                  <span className="text-sm font-semibold text-gray-900">
                    {pr.mall_name}
                    {i === 0 && p.prices.length > 1 && (
                      <span className="ml-2 rounded bg-red-50 px-1.5 py-0.5 text-xs font-bold text-red-700">최저가</span>
                    )}
                  </span>
                  <span className="text-xs text-gray-600">가격 확인일 {kstMonthDay(pr.collected_at)}</span>
                </div>
                <div className="flex flex-none items-center gap-3">
                  <span className="text-base font-bold text-gray-900">{won(pr.price)}원</span>
                  <a
                    href={pr.link}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="rounded-full bg-[#7B4BC4] px-3 py-2 text-xs font-bold text-white"
                  >
                    보러 가기
                  </a>
                </div>
              </li>
            ))}
          </ul>
        )}
        <p className="text-xs leading-relaxed text-gray-600">
          가격은 확인일 기준이라 쇼핑몰의 현재 가격과 다를 수 있어요. 구매 전 쇼핑몰에서 최종 가격을 확인해 주세요.
        </p>
      </section>
    </main>
  );
}
