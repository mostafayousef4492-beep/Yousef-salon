-- استبدال النقاط بخدمة: العميل يختار خدمة، النقاط تتخصم، والباقي يدفعه عند الكاشير.
-- بيعمل كوبون عادي (نفس نظام الكوبونات الحالي) بقيمة خصم ثابتة، فمفيش تعديل في الكاشير.
-- الإعدادات (في app_settings، قابلة للتغيير): points_egp_value = قيمة النقطة بالجنيه (الافتراضي 0.2 = 100 نقطة بـ 20 جنيه)
--                                          service_redeem_min_points = أقل عدد نقاط للاستبدال (الافتراضي 100)
-- آمن للتكرار.
create sequence if not exists public.loyalty_svc_seq start 1000000;

create or replace function public.p28_svc_quote(p_points int, p_price numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rate numeric; minp int; need int; use_ int; disc numeric;
begin
  rate := coalesce(nullif((select value #>> '{}' from app_settings where key = 'points_egp_value'), '')::numeric, 0.2);
  if rate <= 0 then rate := 0.2; end if;
  minp := coalesce(nullif((select value #>> '{}' from app_settings where key = 'service_redeem_min_points'), '')::int, 100);
  need := ceil(p_price / rate);
  use_ := greatest(least(coalesce(p_points, 0), need), 0);
  disc := least(p_price, round(use_ * rate, 2));
  return jsonb_build_object('need', need, 'use', use_, 'discount', disc, 'pay', p_price - disc, 'min', minp, 'ok', use_ >= minp and disc > 0);
end $$;
revoke all on function public.p28_svc_quote(int, numeric) from public, anon, authenticated;

create or replace function public.redeem_service_options() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'سجّل دخول الأول'; end if;
  if not p11_cfg_bool('ff_loyalty', true) then raise exception 'برنامج الولاء متوقف'; end if;
  return jsonb_build_object('points', c.points, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'price', s.price) || p28_svc_quote(c.points, s.price) order by s.price, s.id)
    from services s where s.active and s.price > 0), '[]'::jsonb));
end $$;
revoke all on function public.redeem_service_options() from public, anon;
grant execute on function public.redeem_service_options() to authenticated;

create or replace function public.redeem_service(p_service bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c customers; s services; q jsonb; v_use int; v_disc numeric; v_rw bigint; v_code text; v_name text;
begin
  select * into c from customers where user_id = auth.uid() for update;
  if c.id is null then raise exception 'سجّل دخول الأول'; end if;
  if not p11_cfg_bool('ff_loyalty', true) then raise exception 'برنامج الولاء متوقف'; end if;
  select * into s from services where id = p_service and active and price > 0;
  if s.id is null then raise exception 'الخدمة دي مش متاحة'; end if;
  q := p28_svc_quote(c.points, s.price);
  if not (q->>'ok')::boolean then raise exception 'محتاج على الأقل % نقطة عشان تستبدل (عندك %)', q->>'min', c.points; end if;
  v_use := (q->>'use')::int; v_disc := (q->>'discount')::numeric;
  v_name := 'استبدال نقاط: ' || s.name || ' — خصم ' || trim(trailing '.' from trim(trailing '0' from v_disc::text)) || ' ج';
  v_rw := nextval('loyalty_svc_seq');
  insert into loyalty_rewards(id, name, cost, kind, value, service_id, active) values (v_rw, v_name, v_use, 'amount', v_disc, s.id, false);
  perform add_points(c.id, -v_use, 'redeem', null, v_name);
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into loyalty_redemptions(customer_id, reward_id, code) values (c.id, v_rw, v_code);
  return jsonb_build_object('code', v_code, 'service', s.name, 'price', s.price, 'points_used', v_use, 'discount', v_disc, 'pay', s.price - v_disc);
end $$;
revoke all on function public.redeem_service(bigint) from public, anon;
grant execute on function public.redeem_service(bigint) to authenticated;
