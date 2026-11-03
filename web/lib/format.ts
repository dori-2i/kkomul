export const won = (n: number) => n.toLocaleString("ko-KR");

// DB의 시각(세계 표준시로 옴)을 한국 날짜 MM/DD로 표시
export const kstMonthDay = (iso: string) => {
  const parts = new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("month")}/${get("day")}`;
};
