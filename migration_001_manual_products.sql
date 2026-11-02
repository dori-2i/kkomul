-- =====================================================================
-- migration_001: 네이버 쇼핑 API 종료에 따라 상품을 직접 입력하는 방식으로 전환
-- Supabase SQL Editor에서 한 번만 실행하세요.
-- =====================================================================

-- 1) 네이버 상품번호 대신 우리가 정하는 상품코드(예: P001)를 기준으로 상품을 구분
alter table products rename column naver_product_id to sku;
alter table products alter column sku set not null;

-- 2) 최저가 뷰: "최근 24시간 수집분" 대신 "판매처별 가장 최근 가격" 중 최저가
--    (직접 입력은 매일 수집하지 않으므로 기존 기준이면 결과가 비어 버림)
create or replace view v_product_lowest_price as
with latest as (
  select distinct on (product_id, mall_name)
         product_id, mall_name, price, link, collected_at
  from product_prices
  order by product_id, mall_name, collected_at desc
)
select distinct on (product_id)
       product_id, mall_name, price, link, collected_at
from latest
order by product_id, price asc, collected_at desc;
