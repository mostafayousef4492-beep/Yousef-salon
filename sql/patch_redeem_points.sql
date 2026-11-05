-- عدد نقاط ثابت لكل خدمة تتستبدل بنقاط: services.redeem_points.
--  • لو محدد (مثلاً قصة شعر = 300 نقطة): العميل بيدفع النقاط دي وياخد الخدمة كاملة (الخصم = سعرها، المطلوب 0).
--  • لو فاضي: بيشتغل زي الأول (خصم حسب النقاط اللي معاه).
--  • الخدمة لازم تكون redeemable كمان (patch_redeem_services_only.sql الأول). آمن للتكرار.
begin;
alter table public.services add column if not exists redeem_points int check (redeem_points is null or redeem_points > 0);

create or replace function public.p29_svc_q(p_points int, p_price numeric, p_cost int) returns jsonb
language sql stable set search_path = public as $$
  select case when p_cost is not null and p_cost > 0
    then jsonb_build_object('ok', p_points >= p_cost, 'min', p_cost, 'use', p_cost, 'discount', p_price, 'pay', 0)
    else p28_svc_quote(p_points, p_price) end $$;

create or replace function public.redeem_service_options() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'سجّل دخول الأول'; end if;
  if not p11_cfg_bool('ff_loyalty', true) then raise exception 'برنامج الولاء متوقف'; end if;
  return jsonb_build_object('points', c.points, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'price', s.price) || p29_svc_q(c.points, s.price, s.redeem_points) order by s.price, s.id)
    from services s where s.active and s.price > 0 and s.redeemable), '[]'::jsonb));
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
  select * into s from services where id = p_service and active and price > 0 and redeemable;
  if s.id is null then raise exception 'الخدمة دي مش متاحة'; end if;
  q := p29_svc_q(c.points, s.price, s.redeem_points);
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
commit;
commit;
