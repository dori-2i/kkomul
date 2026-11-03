import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "꼬물샵",
  description: "우리 아기 키와 개월 수에 맞는 옷 사이즈와 참고 가격을 알려 드려요.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ko" className="h-full antialiased">
      <body className="flex min-h-full flex-col">{children}</body>
    </html>
  );
}
