-- =====================================================================
-- migration_002: 포인트 제도 (출석체크, 최저가 도전)
-- Supabase SQL Editor에서 migration_001 다음에 한 번 실행하세요.
--
-- 규칙 (point_rules 테이블에서 숫자만 바꾸면 조정 가능)
--   출석체크      하루 1회   5p
--   최저가 도전   하루 5회  10p  — 운영자가 확인하고, 기존 최저가보다 쌀 때만 지급
-- =====================================================================


-- 1) 포인트 규칙
create table point_rules (
  code         varchar(20)  primary key,
  points       integer      not null check (points > 0),
  daily_limit  smallint     check (daily_limit > 0),   -- 하루 최대 지급 횟수 (null = 제한 없음)
  description  varchar(100) not null,
  is_active    boolean      not null default true
);

insert into point_rules(code, points, daily_limit, description) values
  ('attendance',   5, 1, '출석체크'),
  ('lowest_price', 10, 5, '최저가 도전: 기존 최저가보다 싼 가격 제보가 승인됨');


-- 2) 포인트 내역 (지급·사용·조정을 모두 한 줄씩 기록. 잔액은 합계로 계산)
create table point_ledger (
  id          bigint generated always as identity primary key,
  user_id     bigint      not null references users(id),
  rule_code   varchar(20) references point_rules(code),   -- 사용·운영자 조정이면 null
  amount      integer     not null check (amount <> 0),   -- 지급 +, 사용 -
  ref_type    varchar(20),                                 -- 'attendance', 'price_report' 등
  ref_id      bigint,
  memo        varchar(200),
  created_at  timestamptz not null default now(),
  unique (rule_code, ref_type, ref_id)                    -- 같은 근거로 두 번 지급 방지
);
create index point_ledger_user_idx on point_ledger(user_id, created_at desc);

create view v_point_balance as
select user_id, sum(amount)::integer as balance
from point_ledger
group by user_id;


-- 3) 출석 기록 (한국 날짜 기준 하루 한 번)
create table attendance (
  user_id   bigint not null references users(id) on delete cascade,
  att_date  date   not null,
  primary key (user_id, att_date)
);


-- 4) 가격 제보 (최저가 도전)
create table price_reports (
  id             bigint generated always as identity primary key,
  user_id        bigint        not null references users(id),
  product_id     bigint        not null references products(id),
  mall_name      varchar(100)  not null,
  price          integer       not null check (price > 0),
  link           varchar(1000) not null check (link ~ '^https?://'),
  seen_on        date          not null default (now() at time zone 'Asia/Seoul')::date,
  status         varchar(10)   not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  is_lowest      boolean,                     -- 승인 시점에 기존 최저가보다 쌌는지
  points_given   integer       not null default 0,
  reject_reason  varchar(200),
  reviewed_by    bigint        references users(id),
  reviewed_at    timestamptz,
  created_at     timestamptz   not null default now(),
  check ((status = 'pending') = (reviewed_at is null))
);
-- 같은 사람이 같은 상품·판매처를 하루에 여러 번 제보하지 못하게
create unique index price_reports_daily_uq on price_reports(user_id, product_id, mall_name, seen_on);
create index price_reports_queue_idx on price_reports(created_at) where status = 'pending';


-- 5) 함수: 오늘 이 규칙으로 몇 번 받았는지
create or replace function points_today(p_user bigint, p_rule varchar)
returns integer language sql stable as $$
  select count(*)::integer
  from point_ledger
  where user_id = p_user
    and rule_code = p_rule
    and (created_at at time zone 'Asia/Seoul')::date = (now() at time zone 'Asia/Seoul')::date
$$;


-- 6) 함수: 출석체크. 받은 포인트를 돌려줌 (이미 출석했으면 0)
create or replace function check_in(p_user bigint)
returns integer language plpgsql as $$
declare
  v_today  date := (now() at time zone 'Asia/Seoul')::date;
  v_points integer;
begin
  insert into attendance(user_id, att_date) values (p_user, v_today)
  on conflict do nothing;
  if not found then
    return 0;
  end if;

  select points into v_points from point_rules where code = 'attendance' and is_active;
  if v_points is null then
    return 0;
  end if;

  insert into point_ledger(user_id, rule_code, amount, ref_type, ref_id, memo)
  values (p_user, 'attendance', v_points, 'attendance', null,
          '출석체크 ' || to_char(v_today, 'YYYY-MM-DD'));   -- 중복 출석은 attendance 기본키가 막음
  return v_points;
end;
$$;


-- 7) 함수: 운영자가 가격 제보를 승인. 지급한 포인트를 돌려줌
--    - 상품 가격 기록(product_prices)에 반영
--    - 기존 최저가보다 쌀 때만, 하루 한도 안에서 포인트 지급
create or replace function approve_price_report(p_report bigint, p_admin bigint)
returns integer language plpgsql as $$
declare
  r          price_reports%rowtype;
  v_lowest   integer;
  v_rule     point_rules%rowtype;
  v_points   integer := 0;
begin
  select * into r from price_reports where id = p_report for update;
  if not found then
    raise exception '제보 %번이 없어요.', p_report;
  end if;
  if r.status <> 'pending' then
    raise exception '제보 %번은 이미 처리됐어요 (%).', p_report, r.status;
  end if;
  if r.user_id = p_admin then
    raise exception '본인 제보는 직접 승인할 수 없어요.';
  end if;

  select price into v_lowest from v_product_lowest_price where product_id = r.product_id;

  insert into product_prices(product_id, mall_name, price, link, collected_at)
  values (r.product_id, r.mall_name, r.price, r.link,
          (r.seen_on::timestamp at time zone 'Asia/Seoul'));

  select * into v_rule from point_rules where code = 'lowest_price' and is_active;
  if (v_lowest is null or r.price < v_lowest)
     and v_rule.code is not null
     and (v_rule.daily_limit is null or points_today(r.user_id, 'lowest_price') < v_rule.daily_limit) then
    insert into point_ledger(user_id, rule_code, amount, ref_type, ref_id, memo)
    values (r.user_id, 'lowest_price', v_rule.points, 'price_report', r.id, '최저가 도전 성공');
    v_points := v_rule.points;
  end if;

  update price_reports
     set status = 'approved',
         is_lowest = (v_lowest is null or r.price < v_lowest),
         points_given = v_points,
         reviewed_by = p_admin,
         reviewed_at = now()
   where id = p_report;
  return v_points;
end;
$$;


-- 8) 함수: 운영자가 가격 제보를 반려
create or replace function reject_price_report(p_report bigint, p_admin bigint, p_reason varchar)
returns void language plpgsql as $$
begin
  update price_reports
     set status = 'rejected', reject_reason = p_reason, reviewed_by = p_admin, reviewed_at = now()
   where id = p_report and status = 'pending';
  if not found then
    raise exception '대기 중인 제보 %번이 없어요.', p_report;
  end if;
end;
$$;


-- 9) 새 테이블도 RLS 켜기 (앱용 접근 규칙은 화면 만들 때 추가)
alter table point_rules   enable row level security;
alter table point_ledger  enable row level security;
alter table attendance    enable row level security;
alter table price_reports enable row level security;
