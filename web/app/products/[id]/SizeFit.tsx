"use client";

import { useEffect, useState } from "react";
import { AGE_OPTIONS } from "@/lib/growth";
import { getSizeFit, type SizeFitRow } from "@/lib/products";

const VERDICT_STYLE: Record<string, string> = {
  "작아요": "bg-orange-100 text-orange-900",
  "딱 맞아요": "bg-[#7B4BC4] text-white",
  "넉넉해요": "bg-blue-100 text-blue-900",
  "아직 너무 커요": "bg-gray-200 text-gray-800",
};

function monthRange(min: number | null, max: number | null) {
  if (min === null && max === null) return null;
  const fmt = (m: number) => (m >= 24 && m % 12 === 0 ? `${m / 12}세` : `${m}개월`);
  if (min !== null && max !== null) return `${fmt(min)}~${fmt(max)}`;
  return min !== null ? `${fmt(min)}~` : `~${fmt(max!)}`;
}

export default function SizeFit({ productId, hasSizes }: { productId: number; hasSizes: boolean }) {
  const [ageIndex, setAgeIndex] = useState(2); // 6개월
  const [heightText, setHeightText] = useState(String(AGE_OPTIONS[2].height));
  const [edited, setEdited] = useState(false);
  const [rows, setRows] = useState<SizeFitRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const age = AGE_OPTIONS[ageIndex];
  const height = Number(heightText);
  const heightValid = heightText !== "" && height >= 30 && height <= 170;

  useEffect(() => {
    if (!hasSizes || !heightValid) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      getSizeFit(productId, age.month, height)
        .then((r) => !cancelled && (setRows(r), setError(null)))
        .catch((e) => !cancelled && setError(e instanceof Error ? e.message : "사이즈 판정을 불러오지 못했어요."));
    }, 250); // 키를 입력하는 동안 매번 요청하지 않도록 잠깐 기다림
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [productId, hasSizes, age.month, height, heightValid]);

  function pickAge(i: number) {
    setAgeIndex(i);
    setHeightText(String(AGE_OPTIONS[i].height));
    setEdited(false);
  }

  return (
    <section className="flex flex-col gap-4 rounded-2xl bg-white p-4 shadow-sm">
      <h2 className="text-base font-bold text-gray-900">사이즈 핏 체크</h2>

      {!hasSizes ? (
        <p className="text-sm text-gray-600">이 상품은 사이즈 정보가 아직 없어요.</p>
      ) : (
        <>
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-2 text-sm font-semibold text-gray-800">아기 개월 수</legend>
            <div className="grid grid-cols-5 gap-1.5">
              {AGE_OPTIONS.map((a, i) => (
                <button
                  key={a.month}
                  type="button"
                  onClick={() => pickAge(i)}
                  aria-pressed={i === ageIndex}
                  className={`min-h-11 rounded-lg border text-xs ${
                    i === ageIndex
                      ? "border-gray-900 bg-gray-900 font-bold text-white"
                      : "border-gray-300 bg-white text-gray-900"
                  }`}
                >
                  {a.label}
                </button>
              ))}
            </div>
          </fieldset>

          <div className="flex flex-col gap-1">
            <label htmlFor="baby-height" className="text-sm font-semibold text-gray-800">
              키 (cm)
            </label>
            <input
              id="baby-height"
              type="number"
              inputMode="decimal"
              min={30}
              max={170}
              step={0.1}
              value={heightText}
              onChange={(e) => {
                setHeightText(e.target.value);
                setEdited(true);
              }}
              aria-invalid={!heightValid}
              className="h-12 rounded-xl border border-gray-300 px-4 text-lg font-bold text-gray-900"
            />
            <span className={`text-xs ${heightValid ? "text-gray-600" : "text-red-700"}`}>
              {!heightValid
                ? "30~170 사이의 키를 입력해 주세요."
                : edited
                  ? "직접 입력한 키로 판정해요."
                  : `${age.label} 평균 키(참고값)로 자동 입력했어요. 실제 키로 바꾸면 더 정확해요.`}
            </span>
          </div>

          {error && <p className="rounded-xl bg-red-50 p-3 text-sm text-red-800">{error}</p>}

          {rows && heightValid && (
            <ul className="flex flex-col gap-2" aria-live="polite">
              {rows.map((r) => (
                <li key={r.size_label} className="flex items-center justify-between gap-3 rounded-xl border border-gray-100 p-3">
                  <div className="flex min-w-0 flex-col">
                    <span className="text-base font-black text-gray-900">{r.size_label}</span>
                    <span className="text-xs text-gray-600">
                      {[
                        r.height_min_cm !== null && r.height_max_cm !== null
                          ? `키 ${r.height_min_cm}~${r.height_max_cm}cm`
                          : r.height_max_cm !== null
                            ? `키 ~${r.height_max_cm}cm`
                            : null,
                        monthRange(r.month_min, r.month_max),
                      ]
                        .filter(Boolean)
                        .join(" · ") || "치수 정보 없음"}
                    </span>
                  </div>
                  <div className="flex flex-none flex-col items-end gap-1">
                    {r.verdict ? (
                      <span className={`rounded-lg px-2.5 py-1 text-sm font-bold ${VERDICT_STYLE[r.verdict]}`}>{r.verdict}</span>
                    ) : (
                      <span className="rounded-lg bg-gray-100 px-2.5 py-1 text-sm text-gray-700">
                        {/free|프리/i.test(r.size_label) ? "프리사이즈" : "판정 정보 없음"}
                      </span>
                    )}
                    {r.brand_recommended && (
                      <span className="text-xs font-semibold text-[#55309A]">브랜드 권장 개월</span>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          )}

          <p className="text-xs leading-relaxed text-gray-600">
            평균 성장과 브랜드 사이즈표를 기준으로 한 참고용 안내예요. 브랜드마다 실측이 다르니 구매 전 상세 사이즈표를 꼭 확인해 주세요.
          </p>
        </>
      )}
    </section>
  );
}
