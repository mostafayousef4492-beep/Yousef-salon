-- استبدال النقاط بخدمات معيّنة بس (مش أي حاجة تانية).
--  • services.redeemable = الخدمة دي ينفع تتشتري بنقاط (بتتحدد من شاشة الخدمات في الإدارة).
--  • redeem_service_options / redeem_service بيشتغلوا على الخدمات دي بس (السيرفر بيرفض أي خدمة تانية).
--  • الخصومات العامة (خصم 20 جنيه / 10%) بتتوقف: active=false (ترجّعها من لوحة الإدارة لو حبيت). مكافأة "قصة شعر مجانية" فاضلة لأنها خدمة.
--  • افتراضياً الخدمات المسموحة: قصة شعر، حلاقة ذقن، مسك صنفرة، مسك طمي، حمام كريم (ids 1,2,9,10,4).
-- آمن للتكرار.
begin;
alter table public.services add column if not exists redeemable boolean not null default false;
update public.services set redeemable = true where id in (1,2,4,9,10) and not redeemable
  and not exists (select 1 from services where redeemable);
update public.loyalty_rewards set active = false where active and service_id is null and kind in ('amount','pct');

create or replace function public.redeem_service_options() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'سجّل دخول الأول'; end if;
  if not p11_cfg_bool('ff_loyalty', true) then raise exception 'برنامج الولاء متوقف'; end if;
  return jsonb_build_object('points', c.points, 'items', coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'price', s.price) || p28_svc_quote(c.points, s.price) order by s.price, s.id)
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
commit;
