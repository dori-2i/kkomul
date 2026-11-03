-- =====================================================================
-- migration_012: 웹 앱에서 상품 정보를 누구나 읽을 수 있게 열기
--   - 상품·브랜드·가격·사이즈·이미지·사이즈표: 누구나 읽기만 가능 (쓰기는 불가)
--   - 회원·포인트·신고 등 나머지 테이블은 계속 잠겨 있음
--   - brands.images_allowed: 이미지 사용을 허락받은 브랜드만 true로 바꿔서 사진 표시
-- Supabase SQL Editor에서 migration_011 다음에 한 번 실행하세요.
-- =====================================================================

alter table brands add column images_allowed boolean not null default false;

-- 읽기 허용 규칙 (anon = 로그인 안 한 방문자, authenticated = 로그인한 회원)
create policy "public read brands"         on brands         for select to anon, authenticated using (true);
create policy "public read products"       on products       for select to anon, authenticated using (is_active);
create policy "public read product_sizes"  on product_sizes  for select to anon, authenticated using (true);
create policy "public read product_prices" on product_prices for select to anon, authenticated using (true);
create policy "public read product_images" on product_images for select to anon, authenticated using (true);
create policy "public read size_charts"    on size_charts    for select to anon, authenticated using (true);

-- 읽기 권한만 명시적으로 부여 (쓰기 권한은 주지 않음)
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant select on brands, products, product_sizes, product_prices, product_images, size_charts to %I', r);
      execute format('grant select on v_product_size_chart, v_product_lowest_price to %I', r);
      execute format('grant execute on function size_fit(numeric, numeric) to %I', r);
      execute format('grant execute on function size_verdict(integer, numeric, numeric, numeric, integer, integer) to %I', r);
      execute format('grant execute on function product_size_fit(bigint, integer, numeric) to %I', r);
      execute format('revoke insert, update, delete, truncate on brands, products, product_sizes, product_prices, product_images, size_charts from %I', r);
    end if;
  end loop;
end $$;
