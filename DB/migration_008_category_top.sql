-- =====================================================================
-- migration_008: 상품 카테고리에 '상의(top)' 추가
-- Supabase SQL Editor에서 migration_007 다음에 한 번 실행하세요.
-- =====================================================================

do $$
declare
  c record;
begin
  -- 처음 만들 때 이름 없이 생긴 카테고리 검사 규칙을 찾아 삭제
  for c in
    select conname
    from pg_constraint
    where conrelid = 'products'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%category%'
  loop
    execute format('alter table products drop constraint %I', c.conname);
  end loop;
end $$;

alter table products add constraint products_category_check
  check (category in ('bodysuit', 'romper', 'set', 'top', 'outer', 'legwear', 'acc', 'toy'));
