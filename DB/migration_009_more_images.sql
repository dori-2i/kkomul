-- =====================================================================
-- migration_009: 상품 이미지 최대 10장 → 30장
-- Supabase SQL Editor에서 migration_008 다음에 한 번 실행하세요.
-- =====================================================================

do $$
declare
  c record;
begin
  -- migration_006에서 이름 없이 만든 이미지 순서 검사 규칙을 찾아 삭제
  for c in
    select conname
    from pg_constraint
    where conrelid = 'product_images'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%sort_order%'
  loop
    execute format('alter table product_images drop constraint %I', c.conname);
  end loop;
end $$;

alter table product_images add constraint product_images_sort_order_range
  check (sort_order between 1 and 30);
