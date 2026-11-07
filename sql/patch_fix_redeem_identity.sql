-- إصلاح: استبدال خدمة بنقاط كان بيطلع للعميل رسالة إنجليزي (cannot insert a non-DEFAULT value into column "id" ... GENERATED ALWAYS)
-- السبب: عمود loyalty_rewards.id في قاعدة البيانات "identity ALWAYS" والدالة كانت بتدخّل id يدوي من sequence.
-- الإصلاح: الدالة بقت تسيب القاعدة تولّد الـ id وتاخده بـ returning. مفيش بيانات بتتغيّر.
create or replace function public.redeem_service(p_service bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
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
  insert into loyalty_rewards(name, cost, kind, value, service_id, active)
    values (v_name, v_use, 'amount', v_disc, s.id, false) returning id into v_rw;
  perform add_points(c.id, -v_use, 'redeem', null, v_name);
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into loyalty_redemptions(customer_id, reward_id, code) values (c.id, v_rw, v_code);
  return jsonb_build_object('code', v_code, 'service', s.name, 'price', s.price, 'points_used', v_use, 'discount', v_disc, 'pay', s.price - v_disc);
end $$;
