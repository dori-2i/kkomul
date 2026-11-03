-- =====================================================================
-- migration_006: 상품 이미지 여러 장
--   product_images에 상품별로 최대 10장까지 순서대로 저장
--   products.image_url은 대표 이미지(첫 번째)로 계속 사용
-- Supabase SQL Editor에서 migration_005 다음에 한 번 실행하세요.
-- =====================================================================

create table product_images (
  product_id  bigint        not null references products(id) on delete cascade,
  sort_order  smallint      not null check (sort_order between 1 and 10),
  url         varchar(1000) not null check (url ~ '^https?://'),
  created_at  timestamptz   not null default now(),
  primary key (product_id, sort_order),
  unique (product_id, url)
);

-- 이미 넣어 둔 대표 이미지를 첫 번째 이미지로 옮겨 둠
insert into product_images(product_id, sort_order, url)
select id, 1, image_url
from products
where image_url ~ '^https?://'
on conflict do nothing;

alter table product_images enable row level security;
