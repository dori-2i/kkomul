-- =====================================================================
-- migration_013: 구매 링크 클릭 기록
--   웹 앱의 /go/상품번호 주소가 이 함수를 호출해 클릭을 기록하고,
--   DB에 저장된 판매처 링크를 돌려받아 그곳으로 이동시킴
--   - 이동할 링크는 DB에 있는 값만 쓰므로 주소 조작으로 다른 사이트로 보낼 수 없음
--   - 같은 방문자가 같은 상품·판매처를 10분 안에 다시 누르면 한 번으로 셈
--   - 방문자는 브라우저 쿠키의 임의 번호(session_id)로만 구분하고 IP 등은 저장하지 않음
-- Supabase SQL Editor에서 migration_012 다음에 한 번 실행하세요.
-- =====================================================================

create or replace function record_click(p_product bigint, p_mall varchar,
                                        p_source varchar default 'product',
                                        p_session uuid default null)
returns text
language plpgsql
security definer                 -- 방문자에게 테이블 쓰기 권한을 주지 않고 이 함수로만 기록
set search_path = public
as $$
declare
  v_price product_prices%rowtype;
  v_source varchar := case when p_source in ('home', 'product', 'size_fit', 'toys', 'comment', 'wishlist', 'recent')
                           then p_source else 'product' end;
begin
  -- 판매 중인 상품의 해당 판매처 최근 가격·링크
  select pp.* into v_price
  from product_prices pp
  join products p on p.id = pp.product_id and p.is_active
  where pp.product_id = p_product and pp.mall_name = p_mall
  order by pp.collected_at desc
  limit 1;

  if not found then
    return null;
  end if;

  if p_session is null or not exists (
       select 1 from outbound_clicks
       where session_id = p_session
         and product_id = p_product
         and mall_name = p_mall
         and clicked_at > now() - interval '10 minutes') then
    insert into outbound_clicks(product_id, mall_name, price, session_id, source)
    values (p_product, p_mall, v_price.price, p_session, v_source);
  end if;

  return v_price.link;
end;
$$;

revoke execute on function record_click(bigint, varchar, varchar, uuid) from public;
do $$
declare
  r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = r) then
      execute format('grant execute on function record_click(bigint, varchar, varchar, uuid) to %I', r);
    end if;
  end loop;
end $$;
