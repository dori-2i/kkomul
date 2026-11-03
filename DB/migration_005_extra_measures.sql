-- =====================================================================
-- migration_005: 사이즈표에 '기타 치수' 추가
--   표준 칸(가슴·화장·총장·허리·엉덩이·옆기장·머리)에 없는 치수를
--   {"밑둘레": 26, "깊이": 15} 같은 형태로 저장
-- Supabase SQL Editor에서 migration_004 다음에 한 번 실행하세요.
-- =====================================================================

alter table size_charts
  add column extra_measures jsonb
  check (extra_measures is null or jsonb_typeof(extra_measures) = 'object');

-- 치수가 하나도 없는 줄을 막는 규칙에 기타 치수도 포함
alter table size_charts drop constraint size_charts_has_measure;
alter table size_charts add constraint size_charts_has_measure
  check (num_nonnulls(height_max_cm, month_max, chest_cm, sleeve_cm, length_cm,
                      waist_cm, hip_cm, outseam_cm, head_cm, extra_measures) > 0);
