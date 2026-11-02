-- =====================================================================
-- migration_003: 참여 기능
--   1) 설정값            2) 포인트 상점 · 아기 프로필 꾸미기
--   3) 찜               4) 구매 링크 클릭 기록 (협업 제안용 통계)
--   5) 최근 본 상품       6) 상품별 댓글 (닉네임 기본, 포인트 조건 충족 시 익명)
--   7) 보안 정리: 뷰와 함수가 공개 키로 노출되지 않게 잠금
-- Supabase SQL Editor에서 migration_002 다음에 한 번 실행하세요.
-- =====================================================================


-- =====================================================================
-- 1. 설정값 (숫자만 바꾸면 규칙 조정)
-- =====================================================================
create table app_settings (
  key          varchar(40)  primary key,
  value        integer      not null,
  description  varchar(200) not null
);

insert into app_settings(key, value, description) values
  ('anon_unlock_points',  100, '지금까지 모은 포인트(사용분 제외 전 누적)가 이 값 이상이면 익명 댓글 가능'),
  ('anon_ban_days',        30, '최근 이 기간(일) 안에 제재를 받았으면 익명 댓글 불가'),
  ('comment_daily_limit',  20, '하루 댓글 작성 한도'),
  ('view_keep_days',       90, '최근 본 상품 기록 보관 기간(일)');

create or replace function app_setting(p_key varchar)
returns integer language sql stable as $$
  select value from app_settings where key = p_key
$$;


-- =====================================================================
-- 2. 포인트 상점 · 아기 프로필 꾸미기
-- =====================================================================
create table shop_items (
  code        varchar(30) primary key,
  item_type   varchar(10) not null check (item_type in ('theme', 'sticker', 'frame')),
  name        varchar(50) not null,
  price       integer     not null check (price >= 0),   -- 0이면 기본 제공
  is_active   boolean     not null default true,
  sort_order  smallint    not null default 0
);

insert into shop_items(code, item_type, name, price, sort_order) values
  ('unicorn',        'theme',   '유니콘',          0,   1),
  ('sky',            'theme',   '하늘',            0,   2),
  ('sprout',         'theme',   '새싹',            0,   3),
  ('xmas',           'theme',   '크리스마스',      100, 10),
  ('blossom',        'theme',   '벚꽃',            100, 11),
  ('star_sticker',   'sticker', '반짝 별 스티커',  30,  20),
  ('cloud_sticker',  'sticker', '구름 스티커',     30,  21),
  ('first_bday',     'frame',   '첫 생일 프레임',  80,  30);

-- 아기 테마를 고정 3종에서 상점 아이템으로 확장
alter table babies drop constraint babies_theme_check;
alter table babies add constraint babies_theme_fk foreign key (theme) references shop_items(code);

-- 보유 아이템
create table user_items (
  user_id      bigint      not null references users(id) on delete cascade,
  item_code    varchar(30) not null references shop_items(code),
  acquired_at  timestamptz not null default now(),
  primary key (user_id, item_code)
);

-- 아기 프로필에 붙인 스티커·프레임 (테마는 babies.theme)
create table baby_decor (
  baby_id      bigint      not null references babies(id) on delete cascade,
  slot         varchar(10) not null check (slot in ('sticker', 'frame')),
  item_code    varchar(30) not null references shop_items(code),
  equipped_at  timestamptz not null default now(),
  primary key (baby_id, slot)
);

-- 아이템 구매. 남은 포인트를 돌려줌
create or replace function buy_item(p_user bigint, p_code varchar)
returns integer language plpgsql as $$
declare
  v_item shop_items%rowtype;
  v_bal  integer;
begin
  perform pg_advisory_xact_lock(1, p_user::integer);   -- 같은 사람의 동시 구매 방지
  select * into v_item from shop_items where code = p_code and is_active;
  if not found then
    raise exception '판매 중인 아이템이 아니에요: %', p_code;
  end if;
  if v_item.price = 0 then
    raise exception '기본 아이템이라 구매하지 않아도 돼요.';
  end if;
  if exists (select 1 from user_items where user_id = p_user and item_code = p_code) then
    raise exception '이미 가지고 있는 아이템이에요.';
  end if;
  select coalesce(sum(amount), 0) into v_bal from point_ledger where user_id = p_user;
  if v_bal < v_item.price then
    raise exception '포인트가 부족해요 (보유 %p, 필요 %p).', v_bal, v_item.price;
  end if;

  insert into user_items(user_id, item_code) values (p_user, p_code);
  insert into point_ledger(user_id, rule_code, amount, ref_type, memo)
  values (p_user, null, -v_item.price, 'shop', v_item.name || ' 구매');
  return v_bal - v_item.price;
end;
$$;

-- 아기 프로필에 아이템 적용
create or replace function equip_item(p_user bigint, p_baby bigint, p_code varchar)
returns void language plpgsql as $$
declare
  v_item shop_items%rowtype;
begin
  if not exists (select 1 from babies where id = p_baby and user_id = p_user) then
    raise exception '내 아기 프로필이 아니에요.';
  end if;
  select * into v_item from shop_items where code = p_code;
  if not found then
    raise exception '없는 아이템이에요: %', p_code;
  end if;
  if v_item.price > 0
     and not exists (select 1 from user_items where user_id = p_user and item_code = p_code) then
    raise exception '먼저 아이템을 구매해 주세요.';
  end if;

  if v_item.item_type = 'theme' then
    update babies set theme = p_code where id = p_baby;
  else
    insert into baby_decor(baby_id, slot, item_code) values (p_baby, v_item.item_type, p_code)
    on conflict (baby_id, slot) do update set item_code = excluded.item_code, equipped_at = now();
  end if;
end;
$$;


-- =====================================================================
-- 3. 찜
-- =====================================================================
create table wishlists (
  user_id     bigint      not null references users(id) on delete cascade,
  product_id  bigint      not null references products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, product_id)
);


-- =====================================================================
-- 4. 구매 링크 클릭 기록 (브랜드 협업 제안용)
--    개인을 추적하지 않도록 IP·기기 정보는 저장하지 않음
-- =====================================================================
create table outbound_clicks (
  id          bigint generated always as identity primary key,
  product_id  bigint       not null references products(id),
  mall_name   varchar(100) not null,
  price       integer,                      -- 클릭 당시 화면에 보인 가격
  user_id     bigint       references users(id) on delete set null,
  session_id  uuid,                         -- 비회원 구분용: 브라우저에 저장한 임의 값
  source      varchar(20)  not null default 'product'
              check (source in ('home', 'product', 'size_fit', 'toys', 'comment', 'wishlist', 'recent')),
  clicked_at  timestamptz  not null default now()
);
create index outbound_clicks_time_idx    on outbound_clicks(clicked_at);
create index outbound_clicks_product_idx on outbound_clicks(product_id, clicked_at);

-- 월별 · 브랜드별 · 판매처별 클릭 수와 방문자 수
create view v_clicks_monthly as
select date_trunc('month', c.clicked_at at time zone 'Asia/Seoul')::date      as month,
       coalesce(b.name, '(브랜드 없음)')                                       as brand,
       c.mall_name,
       count(*)                                                                as clicks,
       count(distinct coalesce('u' || c.user_id::text, 's' || c.session_id::text)) as visitors
from outbound_clicks c
join products p on p.id = c.product_id
left join brands b on b.id = p.brand_id
group by 1, 2, 3;


-- =====================================================================
-- 5. 최근 본 상품 (본인에게만 보여 주는 기록)
--    비회원은 브라우저에만 저장하고, 로그인한 사람만 DB에 저장
-- =====================================================================
create table product_views (
  user_id         bigint      not null references users(id) on delete cascade,
  product_id      bigint      not null references products(id) on delete cascade,
  view_date       date        not null,
  view_count      integer     not null default 1,
  last_viewed_at  timestamptz not null default now(),
  primary key (user_id, product_id, view_date)
);
create index product_views_recent_idx on product_views(user_id, last_viewed_at desc);

create or replace function record_view(p_user bigint, p_product bigint)
returns void language sql as $$
  insert into product_views(user_id, product_id, view_date)
  values (p_user, p_product, (now() at time zone 'Asia/Seoul')::date)
  on conflict (user_id, product_id, view_date)
  do update set view_count = product_views.view_count + 1, last_viewed_at = now();
$$;

create view v_recent_views as
select v.user_id,
       v.view_date,
       p.id   as product_id,
       p.sku,
       p.name,
       p.image_url,
       l.price,
       l.mall_name,
       l.link,
       v.view_count,
       v.last_viewed_at,
       exists (select 1 from wishlists w where w.user_id = v.user_id and w.product_id = p.id) as wished
from product_views v
join products p on p.id = v.product_id
left join v_product_lowest_price l on l.product_id = p.id
where v.view_date >= (now() at time zone 'Asia/Seoul')::date - app_setting('view_keep_days');

-- 보관 기간이 지난 기록 삭제. 지운 줄 수를 돌려줌 (매일 한 번 실행 권장)
create or replace function purge_old_views()
returns integer language plpgsql as $$
declare
  n integer;
begin
  delete from product_views
  where view_date < (now() at time zone 'Asia/Seoul')::date - app_setting('view_keep_days');
  get diagnostics n = row_count;
  return n;
end;
$$;


-- =====================================================================
-- 6. 상품별 댓글
--    기본은 닉네임 표시. 포인트 조건을 채운 사람만 익명 선택 가능
--    같은 상품 안에서는 같은 사람이 같은 익명 이름(예: 익명의 토끼)
--    신고는 기존 reports 테이블에 target_type = 'comment'로 접수
-- =====================================================================
create table product_comments (
  id             bigint generated always as identity primary key,
  product_id     bigint       not null references products(id) on delete cascade,
  user_id        bigint       not null references users(id),
  parent_id      bigint       references product_comments(id),   -- 답글
  body           varchar(500) not null check (length(btrim(body)) between 1 and 500),
  is_anonymous   boolean      not null default false,
  anon_label     varchar(20),
  status         varchar(10)  not null default 'visible'
                 check (status in ('visible', 'deleted', 'hidden')),
  hidden_reason  varchar(200),
  hidden_by      bigint       references users(id),
  created_at     timestamptz  not null default now(),
  deleted_at     timestamptz,
  check (is_anonymous = (anon_label is not null)),
  check ((status = 'hidden') = (hidden_by is not null)),
  check ((status = 'deleted') = (deleted_at is not null))
);
create index product_comments_product_idx on product_comments(product_id, created_at);
create index product_comments_user_idx    on product_comments(user_id, created_at);

-- 익명 댓글을 쓸 수 있는지
create or replace function can_post_anonymously(p_user bigint)
returns boolean language sql stable as $$
  select coalesce((select sum(amount) from point_ledger where user_id = p_user and amount > 0), 0)
           >= app_setting('anon_unlock_points')
     and not exists (
           select 1 from sanctions
           where user_id = p_user
             and created_at > now() - make_interval(days => app_setting('anon_ban_days')))
$$;

-- 댓글 작성. 새 댓글 id를 돌려줌
create or replace function post_comment(p_user bigint, p_product bigint, p_body varchar,
                                        p_anonymous boolean default false, p_parent bigint default null)
returns bigint language plpgsql as $$
declare
  v_user    users%rowtype;
  v_label   varchar(20);
  v_n       integer;
  v_id      bigint;
  animals   text[] := array['토끼','고래','다람쥐','고양이','강아지','판다',
                            '펭귄','코알라','부엉이','여우','사슴','수달'];
begin
  select * into v_user from users where id = p_user;
  if not found or v_user.status in ('banned', 'withdrawn') then
    raise exception '댓글을 쓸 수 없는 계정이에요.';
  end if;
  if v_user.status = 'suspended' and v_user.suspended_until > now() then
    raise exception '이용 정지 중이에요 (%까지).', to_char(v_user.suspended_until at time zone 'Asia/Seoul', 'YYYY-MM-DD HH24:MI');
  end if;

  if (select count(*) from product_comments
      where user_id = p_user
        and (created_at at time zone 'Asia/Seoul')::date = (now() at time zone 'Asia/Seoul')::date)
     >= app_setting('comment_daily_limit') then
    raise exception '오늘은 댓글을 더 쓸 수 없어요 (하루 %개).', app_setting('comment_daily_limit');
  end if;

  if p_parent is not null and not exists (
       select 1 from product_comments where id = p_parent and product_id = p_product and status = 'visible') then
    raise exception '답글을 달 수 없는 댓글이에요.';
  end if;

  if p_anonymous then
    if not can_post_anonymously(p_user) then
      raise exception '익명 댓글은 포인트 %p 이상 모은 분부터 쓸 수 있어요.', app_setting('anon_unlock_points');
    end if;
    perform pg_advisory_xact_lock(2, p_product::integer);   -- 같은 상품의 익명 이름 중복 방지
    select anon_label into v_label from product_comments
    where product_id = p_product and user_id = p_user and is_anonymous
    limit 1;
    if v_label is null then
      select count(distinct user_id) into v_n from product_comments
      where product_id = p_product and is_anonymous;
      v_label := '익명의 ' || animals[(v_n % array_length(animals, 1)) + 1]
                 || case when v_n >= array_length(animals, 1)
                         then (v_n / array_length(animals, 1) + 1)::text else '' end;
    end if;
  end if;

  insert into product_comments(product_id, user_id, parent_id, body, is_anonymous, anon_label)
  values (p_product, p_user, p_parent, btrim(p_body), p_anonymous, v_label)
  returning id into v_id;
  return v_id;
end;
$$;

-- 내 댓글 삭제 (누구나 언제든 가능한 기본 권리)
create or replace function delete_my_comment(p_user bigint, p_comment bigint)
returns void language plpgsql as $$
begin
  update product_comments set status = 'deleted', deleted_at = now()
  where id = p_comment and user_id = p_user and status = 'visible';
  if not found then
    raise exception '삭제할 수 있는 내 댓글이 아니에요.';
  end if;
end;
$$;

-- 운영자가 댓글 숨김 (과도한 비난 등). 작성자 동의 없이 가능
create or replace function hide_comment(p_admin bigint, p_comment bigint, p_reason varchar)
returns void language plpgsql as $$
begin
  if not exists (select 1 from users where id = p_admin and role = 'admin') then
    raise exception '운영자만 숨길 수 있어요.';
  end if;
  update product_comments
     set status = 'hidden', hidden_reason = p_reason, hidden_by = p_admin
   where id = p_comment and status <> 'hidden';
  if not found then
    raise exception '숨길 수 있는 댓글이 없어요: %', p_comment;
  end if;
end;
$$;

-- 화면용 댓글 목록: 작성자 id는 내보내지 않고, 익명이면 익명 이름만 보여 줌
create view v_product_comments as
select c.id,
       c.product_id,
       c.parent_id,
       case when c.status <> 'visible' then null
            when c.is_anonymous      then c.anon_label
            else u.nickname end                                   as display_name,
       case c.status
            when 'visible' then c.body
            when 'deleted' then '작성자가 삭제한 댓글이에요.'
            else '운영 정책에 따라 숨겨진 댓글이에요.' end            as body,
       c.status,
       c.created_at
from product_comments c
join users u on u.id = c.user_id;


-- =====================================================================
-- 7. 보안 정리
--  (1) 모든 뷰가 조회하는 사람의 권한(RLS)을 따르게 함.
--      기본값이면 뷰가 RLS를 건너뛰어 공개 키로도 내용이 보일 수 있음
--  (2) 포인트 지급·승인 같은 함수는 공개 키로 직접 호출하지 못하게 막음.
--      앱 화면을 만들 때 로그인 사용자 확인을 거치는 함수로 따로 열어 줌
-- =====================================================================
alter view v_product_size_chart    set (security_invoker = true);
alter view v_product_lowest_price  set (security_invoker = true);
alter view v_user_report_summary   set (security_invoker = true);
alter view v_point_balance         set (security_invoker = true);
alter view v_clicks_monthly        set (security_invoker = true);
alter view v_recent_views          set (security_invoker = true);
alter view v_product_comments      set (security_invoker = true);

do $$
declare
  f record;
  r text;
begin
  for f in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('points_today', 'check_in', 'approve_price_report', 'reject_price_report',
                        'app_setting', 'buy_item', 'equip_item', 'record_view', 'purge_old_views',
                        'can_post_anonymously', 'post_comment', 'delete_my_comment', 'hide_comment')
  loop
    execute format('revoke execute on function %s from public', f.sig);
    foreach r in array array['anon', 'authenticated'] loop
      if exists (select 1 from pg_roles where rolname = r) then
        execute format('revoke execute on function %s from %I', f.sig, r);
      end if;
    end loop;
  end loop;
end $$;

-- 처음부터 있던 테이블도 RLS가 켜져 있는지 한 번 더 보장 (이미 켜져 있으면 그대로)
alter table users             enable row level security;
alter table banned_identities enable row level security;
alter table user_blocks       enable row level security;
alter table babies            enable row level security;
alter table baby_measurements enable row level security;
alter table growth_standards  enable row level security;
alter table brands            enable row level security;
alter table products          enable row level security;
alter table product_sizes     enable row level security;
alter table product_prices    enable row level security;
alter table size_charts       enable row level security;
alter table reports           enable row level security;
alter table sanctions         enable row level security;

alter table app_settings      enable row level security;
alter table shop_items        enable row level security;
alter table user_items        enable row level security;
alter table baby_decor        enable row level security;
alter table wishlists         enable row level security;
alter table outbound_clicks   enable row level security;
alter table product_views     enable row level security;
alter table product_comments  enable row level security;
