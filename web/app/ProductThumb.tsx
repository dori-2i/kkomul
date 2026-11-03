// 상품 사진 자리. 이미지 사용을 허락받은 브랜드(brands.images_allowed)만 실제 사진을 보여 줌
export default function ProductThumb({ src, alt, size = "md" }: { src: string | null; alt: string; size?: "md" | "lg" }) {
  const box = size === "lg" ? "h-64 w-full rounded-2xl" : "h-24 w-24 rounded-xl";
  return (
    <div className={`${box} flex flex-none items-center justify-center overflow-hidden bg-[#F0E8FB] text-[#55309A]`}>
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={alt} className="h-full w-full object-cover" />
      ) : (
        <svg width={size === "lg" ? 72 : 40} height={size === "lg" ? 72 : 40} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" aria-hidden="true">
          <path d="M8 3h8l4 4-3 2.5V13l-2 2v6H9v-6l-2-2V9.5L4 7z" />
          <path d="M10 3a2 2 0 0 0 4 0" />
        </svg>
      )}
    </div>
  );
}
