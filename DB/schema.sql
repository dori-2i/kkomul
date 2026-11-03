-- =====================================================================
-- 꼬물샵(가칭) DB 스키마 v0.1
-- 대상: PostgreSQL 15+ (Supabase에서도 그대로 실행 가능)
-- 범위: 회원 · 아기 프로필 · 상품/가격 · 사이즈표 · 신고/제재
-- 커뮤니티(게시글/댓글/채팅) 테이블은 익명 여부 결정 후 추가
-- =====================================================================


-- =====================================================================
-- 1. 회원
-- =====================================================================

create table users (
  id               bigint generated always as identity primary key,
  email            varchar(255) not null unique,
  nickname         varchar(20)  not null unique,   -- 아이디 표시 방식이면 이 값을 노출
  ci_hash          char(64) unique,                -- 본인인증 고유값(CI)의 SHA-256 해시. 1인 1계정 보장
  role             varchar(10)  not null default 'user'
                   check (role in ('user', 'admin')),
  status           varchar(12)  not null default 'active'
                   check (status in ('active', 'suspended', 'banned', 'withdrawn')),
  suspended_until  timestamptz,                    -- status = 'suspended'일 때 해제 시각
  marketing_agree  boolean      not null default false,
  created_at       timestamptz  not null default now(),
  withdrawn_at     timestamptz,
  check (status <> 'suspended' or suspended_until is not null)
);

-- 영구 제한된 사람의 재가입 차단용. 탈퇴로 users 행이 정리돼도 남겨 둔다.
create table banned_identities (
  ci_hash    char(64)     primary key,
  reason     varchar(200),
  banned_at  timestamptz  not null default now()
);

-- 내 화면에서 특정 사용자 숨기기 (신고 처리와 별개로 즉시 적용)
create table user_blocks (
  user_id          bigint not null references users(id) on delete cascade,
  blocked_user_id  bigint not null references users(id) on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (user_id, blocked_user_id),
  check (user_id <> blocked_user_id)
);


-- =====================================================================
-- 2. 아기 프로필
-- =====================================================================

create table babies (
  id          bigint generated always as identity primary key,
  user_id     bigint      not null references users(id) on delete cascade,
  nickname    varchar(20) not null,                  -- '첫째', '조카' 등
  birth_date  date        not null,                  -- 개월 수는 저장하지 않고 매번 계산
  sex         char(1)     check (sex in ('F', 'M')), -- 선택 입력. 성장도표 조회에만 사용
  theme       varchar(10) not null default 'sprout'
              check (theme in ('unicorn', 'sky', 'sprout')),
  created_at  timestamptz not null default now()
);
create index babies_user_idx on babies(user_id);

-- 키/몸무게 기록. 가장 최근 값을 사이즈 판정에 사용
create table baby_measurements (
  id           bigint generated always as identity primary key,
  baby_id      bigint       not null references babies(id) on delete cascade,
  measured_on  date         not null,
  height_cm    numeric(4,1) check (height_cm between 30 and 130),
  weight_kg    numeric(4,2) check (weight_kg between 1 and 30),
  unique (baby_id, measured_on),
  check (height_cm is not null or weight_kg is not null)
);

-- 개월별 평균 성장 기준 (키를 입력하지 않았을 때 사용)
create table growth_standards (
  sex         char(1)      not null check (sex in ('F', 'M')),
  age_month   smallint     not null check (age_month between 0 and 36),
  height_p3   numeric(4,1) not null,
  height_p50  numeric(4,1) not null,
  height_p97  numeric(4,1) not null,
  weight_p50  numeric(4,2) not null,
  source      varchar(50)  not null,   -- 예: '2017 소아청소년 성장도표'
  primary key (sex, age_month)
);


-- =====================================================================
-- 3. 상품 · 가격
-- =====================================================================

create table brands (
  id           bigint generated always as identity primary key,
  name         varchar(100) not null unique,
  homepage     varchar(500),
  partnership  varchar(10)  not null default 'none'
               check (partnership in ('none', 'affiliate', 'partner')),  -- 협업 단계
  created_at   timestamptz  not null default now()
);

create table products (
  id                bigint generated always as identity primary key,
  brand_id          bigint       references brands(id),
  name              varchar(200) not null,
  category          varchar(20)  not null
                    constraint products_category_check
                    check (category in ('bodysuit', 'romper', 'set', 'top', 'outer', 'legwear', 'acc', 'toy')),
  sku               varchar(30)  not null unique, -- 우리가 정하는 상품코드 (예: P001)
  image_url         varchar(1000),
  list_price        integer      check (list_price >= 0),   -- 정가
  month_min         smallint     check (month_min >= 0),    -- 추천 개월 수 (주로 장난감용)
  month_max         smallint,
  is_active         boolean      not null default true,
  created_at        timestamptz  not null default now(),
  check (month_max is null or month_min is null or month_min <= month_max)
);
create index products_category_idx on products(category) where is_active;

-- 상품 이미지 (최대 30장, 1번이 대표. products.image_url과 같은 값)
create table product_images (
  product_id  bigint        not null references products(id) on delete cascade,
  sort_order  smallint      not null
              constraint product_images_sort_order_range check (sort_order between 1 and 30),
  url         varchar(1000) not null check (url ~ '^https?://'),
  created_at  timestamptz   not null default now(),
  primary key (product_id, sort_order),
  unique (product_id, url)
);
alter table product_images enable row level security;

-- 이 상품이 판매하는 사이즈 목록
create table product_sizes (
  product_id  bigint      not null references products(id) on delete cascade,
  size_label  varchar(10) not null,            -- '70', '80', 'FREE'
  in_stock    boolean     not null default true,
  primary key (product_id, size_label)
);

-- 판매처별 가격 기록 (가격을 확인할 때마다 한 줄씩 쌓임)
create table product_prices (
  id            bigint generated always as identity primary key,
  product_id    bigint        not null references products(id) on delete cascade,
  mall_name     varchar(100)  not null,
  price         integer       not null check (price >= 0),
  link          varchar(1000) not null,
  collected_at  timestamptz   not null default now()
);
create index product_prices_recent_idx on product_prices(product_id, collected_at desc);


-- =====================================================================
-- 4. 사이즈표
-- 브랜드 공통표 또는 상품 전용표 중 하나. 상품 전용표가 있으면 그걸 우선 사용.
-- =====================================================================

create table size_charts (
  id             bigint generated always as identity primary key,
  brand_id       bigint       references brands(id)   on delete cascade,
  product_id     bigint       references products(id) on delete cascade,
  size_label     varchar(10)  not null,
  height_min_cm  numeric(4,1),
  height_max_cm  numeric(4,1),               -- 판정 기준: 이 옷이 맞는 키의 상한
  weight_min_kg  numeric(4,2),
  weight_max_kg  numeric(4,2),
  note           varchar(200),
  month_min      smallint     constraint size_charts_month_min_range check (month_min between 0 and 144),
  month_max      smallint     constraint size_charts_month_max_range check (month_max between 0 and 144),
  chest_cm       numeric(4,1) check (chest_cm   between 20 and 120),  -- 가슴둘레
  sleeve_cm      numeric(4,1) check (sleeve_cm  between 5  and 80),   -- 화장
  length_cm      numeric(4,1) check (length_cm  between 10 and 130),  -- 총장
  waist_cm       numeric(4,1) check (waist_cm   between 20 and 100),  -- 허리둘레
  hip_cm         numeric(4,1) check (hip_cm     between 20 and 120),  -- 엉덩이둘레
  outseam_cm     numeric(4,1) check (outseam_cm between 10 and 100),  -- 옆기장
  head_cm        numeric(4,1) check (head_cm    between 25 and 60),   -- 머리둘레
  shoulder_cm    numeric(4,1) check (shoulder_cm    between 10 and 60),   -- 어깨너비
  sleeve_len_cm  numeric(4,1) check (sleeve_len_cm  between 3  and 80),   -- 소매길이 (화장과 다름)
  rise_cm        numeric(4,1) check (rise_cm        between 5  and 60),   -- 밑위길이
  bottom_circ_cm numeric(4,1) check (bottom_circ_cm between 10 and 120),  -- 밑둘레
  extra_measures jsonb        check (extra_measures is null or jsonb_typeof(extra_measures) = 'object'),
                                                                       -- 기타 치수 {"밑둘레": 26}
  check ((brand_id is not null) <> (product_id is not null)),
  check (height_min_cm is null or height_min_cm < height_max_cm),
  constraint size_charts_months_chk
    check (month_min is null or month_max is null or month_min <= month_max),
  constraint size_charts_has_measure
    check (num_nonnulls(height_max_cm, month_max, chest_cm, sleeve_cm, length_cm,
                        waist_cm, hip_cm, outseam_cm, head_cm,
                        shoulder_cm, sleeve_len_cm, rise_cm, bottom_circ_cm,
                        extra_measures) > 0)
);
create unique index size_charts_brand_uq   on size_charts(brand_id, size_label)   where brand_id   is not null;
create unique index size_charts_product_uq on size_charts(product_id, size_label) where product_id is not null;

-- 사이즈 판정 함수(키 상한만 아는 간단 판정)와 상세 판정 함수는 아래 v_product_size_chart 다음에 정의

-- 상품별 사이즈의 키 상한: 상품 전용표 → 브랜드 공통표 → 숫자 라벨 그대로(국내 표기 관례) 순서로 결정
create view v_product_size_chart as
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

-- 기존 함수도 5cm 기준으로 (키 최대값만 아는 경우의 간단 판정)
create or replace function size_fit(baby_height numeric, size_max numeric)
returns text
language sql immutable
as $$
  select case
    when baby_height is null or size_max is null then null
    when baby_height > size_max                  then '작아요'
    when size_max - baby_height <= 5             then '딱 맞아요'
    when size_max - baby_height <= 10            then '넉넉해요'
    else                                              '아직 너무 커요'
  end
$$;

-- 새 판정 함수
--   verdict           : 작아요 / 딱 맞아요 / 넉넉해요 / 아직 너무 커요 (판정 불가면 null)
--   basis             : brand_range(브랜드 키 범위로 판정) / max_only(키 상한으로 판정)
--   brand_recommended : 아기 개월이 브랜드 권장 개월 안인지
create or replace function size_verdict(p_month integer, p_height numeric,
                                        p_hmin numeric, p_hmax numeric,
                                        p_mmin integer, p_mmax integer)
returns table (verdict text, basis text, brand_recommended boolean)
language sql immutable
as $$
  with x as (
    select coalesce(p_month between p_mmin and p_mmax, false) as rec
  )
  select
    case
      when p_height is null or p_hmax is null then null
      when p_height > p_hmax then '작아요'
      when p_hmin is not null and p_height >= p_hmin then '딱 맞아요'
      when p_hmin is not null and p_hmin - p_height <= 5 then '넉넉해요'
      when p_hmin is null and p_hmax - p_height <= 5 then '딱 맞아요'
      when p_hmin is null and p_hmax - p_height <= 10 then '넉넉해요'
      when x.rec then '넉넉해요'
      else '아직 너무 커요'
    end,
    case
      when p_height is null or p_hmax is null then null
      when p_hmin is not null then 'brand_range'
      else 'max_only'
    end,
    x.rec
  from x
$$;

-- 상품 하나의 사이즈별 판정 (화면에서 바로 쓰는 함수)
--   예: select * from product_size_fit(1, 6, 67.6);
create or replace function product_size_fit(p_product bigint, p_month integer, p_height numeric)
returns table (size_label varchar, in_stock boolean,
               height_min_cm numeric, height_max_cm numeric,
               month_min smallint, month_max smallint,
               verdict text, basis text, brand_recommended boolean)
language sql stable
as $$
  select v.size_label, v.in_stock,
         c.height_min_cm, v.height_max_cm,
         c.month_min, c.month_max,
         s.verdict, s.basis, s.brand_recommended
  from v_product_size_chart v
  left join size_charts c on c.id = v.size_chart_id
  cross join lateral size_verdict(p_month, p_height, c.height_min_cm, v.height_max_cm,
                                  c.month_min, c.month_max) s
  where v.product_id = p_product
  order by v.height_max_cm nulls last, v.size_label
$$;

-- 상품별 현재 최저가 (판매처별 가장 최근 가격 중 최저가)
create view v_product_lowest_price as
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


-- =====================================================================
-- 5. 신고 · 제재
-- target_type/target_id는 커뮤니티 테이블이 확정되면 연결한다.
-- =====================================================================

create table reports (
  id              bigint generated always as identity primary key,
  reporter_id     bigint       not null references users(id),
  target_user_id  bigint       not null references users(id),
  target_type     varchar(10)  not null check (target_type in ('post', 'comment', 'message')),
  target_id       bigint       not null,
  reason          varchar(10)  not null check (reason in ('abuse', 'spam', 'privacy', 'other')),
  detail          varchar(500),
  status          varchar(10)  not null default 'pending'
                  check (status in ('pending', 'accepted', 'rejected')),
  reviewed_by     bigint       references users(id),
  reviewed_at     timestamptz,
  created_at      timestamptz  not null default now(),
  unique (reporter_id, target_type, target_id),   -- 같은 대상은 한 사람이 한 번만 신고
  check (reporter_id <> target_user_id),
  check ((status = 'pending') = (reviewed_at is null))
);
create index reports_target_user_idx on reports(target_user_id, status);
create index reports_queue_idx       on reports(created_at) where status = 'pending';

create table sanctions (
  id            bigint generated always as identity primary key,
  user_id       bigint      not null references users(id),
  level         varchar(10) not null check (level in ('7d', '30d', 'permanent')),
  reporter_count integer    not null,     -- 적용 시점의 누적 신고자 수(서로 다른 사람)
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz,              -- 영구면 null
  created_by    bigint      references users(id),
  created_at    timestamptz not null default now(),
  check ((level = 'permanent') = (ends_at is null))
);
create index sanctions_user_idx on sanctions(user_id);

-- 운영자 화면용: 사용자별 누적 신고자 수와 권장 제재 단계
-- 서로 다른 사람 3명 → 7일, 10명 → 30일, 15명 또는 정지 3회 → 영구
create view v_user_report_summary as
with r as (
  select target_user_id as user_id,
         count(distinct reporter_id) filter (where status = 'accepted') as accepted_reporters,
         count(*)                    filter (where status = 'pending')  as pending_reports
  from reports
  group by target_user_id
),
s as (
  select user_id, count(*) as sanction_count
  from sanctions
  group by user_id
)
select u.id as user_id,
       u.nickname,
       u.status,
       coalesce(r.accepted_reporters, 0) as accepted_reporters,
       coalesce(r.pending_reports, 0)    as pending_reports,
       coalesce(s.sanction_count, 0)     as sanction_count,
       case
         when coalesce(r.accepted_reporters, 0) >= 15 or coalesce(s.sanction_count, 0) >= 3 then 'permanent'
         when coalesce(r.accepted_reporters, 0) >= 10 then '30d'
         when coalesce(r.accepted_reporters, 0) >= 3  then '7d'
       end as suggested_level
from users u
left join r on r.user_id = u.id
left join s on s.user_id = u.id;
