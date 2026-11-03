-- =====================================================================
-- migration_011: 자주 나오는 치수 4개를 정식 칸으로
--   어깨너비 shoulder_cm / 소매길이 sleeve_len_cm (화장 sleeve_cm과 다름)
--   밑위길이 rise_cm     / 밑둘레 bottom_circ_cm
--   이미 기타치수(extra_measures)에 같은 이름으로 넣은 값은 새 칸으로 옮김
-- Supabase SQL Editor에서 migration_010 다음에 한 번 실행하세요.
-- =====================================================================

alter table size_charts
  add column shoulder_cm    numeric(4,1) check (shoulder_cm    between 10 and 60),   -- 어깨너비
  add column sleeve_len_cm  numeric(4,1) check (sleeve_len_cm  between 3  and 80),   -- 소매길이 (어깨 끝~소매 끝)
  add column rise_cm        numeric(4,1) check (rise_cm        between 5  and 60),   -- 밑위길이
  add column bottom_circ_cm numeric(4,1) check (bottom_circ_cm between 10 and 120);  -- 밑둘레

-- '치수가 하나는 있어야 함' 규칙을 잠시 풀고 데이터를 옮긴 뒤 새 칸까지 포함해 다시 걸기
alter table size_charts drop constraint size_charts_has_measure;

update size_charts
   set shoulder_cm    = coalesce(shoulder_cm,    (extra_measures ->> '어깨너비')::numeric),
       sleeve_len_cm  = coalesce(sleeve_len_cm,  (extra_measures ->> '소매길이')::numeric),
       rise_cm        = coalesce(rise_cm,        (extra_measures ->> '밑위길이')::numeric),
       bottom_circ_cm = coalesce(bottom_circ_cm, (extra_measures ->> '밑둘레')::numeric)
 where extra_measures ?| array['어깨너비', '소매길이', '밑위길이', '밑둘레'];

update size_charts
   set extra_measures = nullif(extra_measures - '어깨너비' - '소매길이' - '밑위길이' - '밑둘레', '{}'::jsonb)
 where extra_measures ?| array['어깨너비', '소매길이', '밑위길이', '밑둘레'];

alter table size_charts add constraint size_charts_has_measure
  check (num_nonnulls(height_max_cm, month_max, chest_cm, sleeve_cm, length_cm,
                      waist_cm, hip_cm, outseam_cm, head_cm,
                      shoulder_cm, sleeve_len_cm, rise_cm, bottom_circ_cm,
                      extra_measures) > 0);
