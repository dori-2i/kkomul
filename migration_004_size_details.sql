-- =====================================================================
-- migration_004: 사이즈표에 개월 수와 부위별 실측 치수 추가
--   - 키 정보가 없는 품목(모자 등)도 등록할 수 있게 키최대를 선택 항목으로 변경
--   - 개월(3M-6M), 가슴둘레, 화장, 총장, 허리둘레, 엉덩이둘레, 옆기장, 머리둘레
-- Supabase SQL Editor에서 migration_003 다음에 한 번 실행하세요.
-- =====================================================================

alter table size_charts alter column height_max_cm drop not null;

alter table size_charts
  add column month_min   smallint     check (month_min between 0 and 72),
  add column month_max   smallint     check (month_max between 0 and 72),
  add column chest_cm    numeric(4,1) check (chest_cm   between 20 and 120),  -- 가슴둘레
  add column sleeve_cm   numeric(4,1) check (sleeve_cm  between 5  and 80),   -- 화장 (목 뒤 중심 ~ 소매 끝)
  add column length_cm   numeric(4,1) check (length_cm  between 10 and 130),  -- 총장
  add column waist_cm    numeric(4,1) check (waist_cm   between 20 and 100),  -- 허리둘레
  add column hip_cm      numeric(4,1) check (hip_cm     between 20 and 120),  -- 엉덩이둘레
  add column outseam_cm  numeric(4,1) check (outseam_cm between 10 and 100),  -- 옆기장 (바지 길이)
  add column head_cm     numeric(4,1) check (head_cm    between 25 and 60);   -- 머리둘레

alter table size_charts add constraint size_charts_months_chk
  check (month_min is null or month_max is null or month_min <= month_max);

-- 치수가 하나도 없는 빈 줄은 막기
alter table size_charts add constraint size_charts_has_measure
  check (num_nonnulls(height_max_cm, month_max, chest_cm, sleeve_cm, length_cm,
                      waist_cm, hip_cm, outseam_cm, head_cm) > 0);

-- 화면에서 상세 치수를 같이 보여 줄 수 있게 사용한 사이즈표의 id를 뷰 끝에 추가
create or replace view v_product_size_chart as
select ps.product_id,
       ps.size_label,
       ps.in_stock,
       coalesce(
         pc.height_max_cm,
         bc.height_max_cm,
         case when ps.size_label ~ '^[0-9]+$' then ps.size_label::numeric end
       ) as height_max_cm,
       case
         when pc.id is not null then 'product'
         when bc.id is not null then 'brand'
         else 'label'
       end as chart_source,
       coalesce(pc.id, bc.id) as size_chart_id
from product_sizes ps
join products p on p.id = ps.product_id
left join size_charts pc on pc.product_id = ps.product_id and pc.size_label = ps.size_label
left join size_charts bc on bc.brand_id = p.brand_id and bc.size_label = ps.size_label;

alter view v_product_size_chart set (security_invoker = true);
