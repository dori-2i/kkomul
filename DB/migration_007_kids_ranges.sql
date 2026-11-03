-- =====================================================================
-- migration_007: 유아동(최대 12세) 사이즈까지 받도록 범위 확대
--   사이즈표 개월 범위 0~72 → 0~144
--   상품 추천 개월은 DB 제한이 없어 변경 없음 (업로드 스크립트 검사만 확대)
-- Supabase SQL Editor에서 migration_006 다음에 한 번 실행하세요.
-- =====================================================================

do $$
declare
  c record;
begin
  -- migration_004에서 이름 없이 만든 개월 범위 검사 규칙을 찾아 삭제
  for c in
    select conname
    from pg_constraint
    where conrelid = 'size_charts'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ~ 'month_(min|max) >= 0\)? AND \(?month_(min|max) <= 72'
  loop
    execute format('alter table size_charts drop constraint %I', c.conname);
  end loop;
end $$;

alter table size_charts
  add constraint size_charts_month_min_range check (month_min between 0 and 144),
  add constraint size_charts_month_max_range check (month_max between 0 and 144);
