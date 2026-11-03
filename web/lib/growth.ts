// 개월별 평균 키 (WHO 성장 기준 중앙값, 남녀 평균에 가까운 참고값, cm)
// 사이즈 판정의 기본값으로만 쓰고, 사용자가 실제 키로 바꿔 입력할 수 있음
export const AGE_OPTIONS: { month: number; label: string; height: number }[] = [
  { month: 0, label: "신생아", height: 49.5 },
  { month: 3, label: "3개월", height: 60.6 },
  { month: 6, label: "6개월", height: 66.7 },
  { month: 9, label: "9개월", height: 71.1 },
  { month: 12, label: "12개월", height: 74.9 },
  { month: 18, label: "18개월", height: 81.5 },
  { month: 24, label: "2세", height: 86.4 },
  { month: 36, label: "3세", height: 95.6 },
  { month: 48, label: "4세", height: 103.0 },
  { month: 60, label: "5세", height: 109.7 },
];
