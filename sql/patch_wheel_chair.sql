-- patch_wheel_chair.sql — لفة مجانية لعجلة الحظ وإنت قاعد على الكرسي بتتحلق
-- لما العميل يبقى على الكرسي (حالة التذكرة «in_service») بيطلعله لفة مجانية واحدة لكل تذكرة، بعيد عن لفة الترحيب والحد اليومي.
-- مابتخصمش نقاط. الجوايز بنفس الأكواد والسقف الشهري بتاع العجلة. السيرفر هو اللي بيتأكد إن العميل فعلاً على الكرسي ومرة واحدة بس للتذكرة.
-- إعداد wheel_chair_free (الافتراضي شغّال) لإيقاف الميزة. لازم patch_lucky_wheel.sql متشغّل. آمن للتشغيل أكتر من مرة.
alter table public.wheel_spins add column if not exists appointment_id bigint;
create unique index if not exists wheel_spins_chair_once on public.wheel_spins(appointment_id) where appointment_id is not null;
insert into public.rule_defs(key, grp, label, hint, kind, min, max, def, danger, kw, sort) values
 ('wheel_chair_free','الولاء','لفة مجانية على الكرسي','العميل بيتحلق (التذكرة in_service) بيلاقي لفة مجانية لكل تذكرة. مابتخصمش نقاط','bool',null,null,'true',false,'عجلة حظ wheel كرسي مجانية chair',125)
on conflict (key) do nothing;

create or replace function public.wheel_status()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c customers; v_on boolean := p11_cfg_bool('wheel_on', false); v_days int := p_ref_cfg('wheel_free_days',0)::int; v_cost int := p_ref_cfg('wheel_cost',50)::int;
        v_max int := p_ref_cfg('wheel_daily_max',3)::int; v_free boolean; v_today int; v_last timestamptz; v_chair bigint;
begin
  select * into c from customers where user_id = auth.uid();
  if not found then return jsonb_build_object('on', false); end if;
  if not v_on then return jsonb_build_object('on', false); end if;
  select max(created_at) into v_last from wheel_spins where customer_id = c.id and free;
  v_free := v_last is null or (v_days > 0 and v_last < now() - make_interval(days => v_days));
  select count(*) into v_today from wheel_spins where customer_id = c.id and created_at > now() - interval '1 day';
  if p11_cfg_bool('wheel_chair_free', true) then
    select a.id into v_chair from appointments a where a.customer_id = c.id and a.status::text = 'in_service' and not exists (select 1 from wheel_spins w where w.appointment_id = a.id) order by a.id limit 1;
  end if;
  return jsonb_build_object('on', true, 'chair', v_chair is not null, 'free', v_free, 'cost', v_cost, 'points', c.points,
    'left_today', greatest(v_max - v_today, 0),
    'slices', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'label', label, 'win', reward_id is not null) order by sort, id), '[]'::jsonb) from wheel_slices where active));
end $$;

create or replace function public.wheel_spin()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c customers; v_days int := p_ref_cfg('wheel_free_days',0)::int; v_cost int := p_ref_cfg('wheel_cost',50)::int; v_max int := p_ref_cfg('wheel_daily_max',3)::int;
        v_cap int := p_ref_cfg('wheel_month_prizes',30)::int; v_last timestamptz; v_free boolean; v_today int; v_tot int; v_pick int; v_acc int := 0;
        s wheel_slices; v_chosen wheel_slices; v_cur numeric; v_code text; v_red bigint; v_month int; v_idx int := 0; v_i int := 0; v_paid int := 0; v_chair bigint;
begin
  if not p11_cfg_bool('wheel_on', false) then raise exception 'عجلة الحظ مش شغّالة دلوقتي'; end if;
  select * into c from customers where user_id = auth.uid() for update;
  if not found then raise exception 'سجّل دخول الأول'; end if;
  if p11_cfg_bool('wheel_chair_free', true) then
    select a.id into v_chair from appointments a where a.customer_id = c.id and a.status::text = 'in_service' and not exists (select 1 from wheel_spins w where w.appointment_id = a.id) order by a.id limit 1;
  end if;
  select count(*) into v_today from wheel_spins where customer_id = c.id and created_at > now() - interval '1 day';
  if v_chair is null and v_today >= v_max then raise exception 'وصلت للحد الأقصى من اللفات النهارده، جرّب بكرة'; end if;
  select max(created_at) into v_last from wheel_spins where customer_id = c.id and free;
  v_free := v_last is null or (v_days > 0 and v_last < now() - make_interval(days => v_days));
  if v_chair is not null then v_free := false; v_paid := 0;
  elsif not v_free and v_cost > 0 then
    if c.points < v_cost then raise exception 'نقاطك مش كفاية للفة (محتاج % نقطة)', v_cost; end if;
    v_paid := v_cost;
  elsif not v_free and v_cost = 0 then v_paid := 0;
  end if;
  select coalesce(sum(weight),0) into v_tot from wheel_slices where active;
  if v_tot <= 0 then raise exception 'العجلة لسه متظبطتش'; end if;
  -- سقف الجوايز الشهري
  select count(*) into v_month from wheel_spins where redemption_id is not null and created_at >= date_trunc('month', now());
  v_pick := floor(random() * v_tot)::int;
  for s in select * from wheel_slices where active order by sort, id loop
    v_acc := v_acc + s.weight;
    if v_pick < v_acc then v_chosen := s; exit; end if;
  end loop;
  if v_chosen.reward_id is not null and v_cap > 0 and v_month >= v_cap then
    select * into v_chosen from wheel_slices where active and reward_id is null order by sort, id limit 1;
    if v_chosen.id is null then raise exception 'العجلة مقفولة لحد الشهر الجاي'; end if;
  end if;
  if v_paid > 0 then perform add_points(c.id, -v_paid, 'wheel', null, 'لفة عجلة الحظ'); end if;
  if v_chosen.reward_id is not null then
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    insert into loyalty_redemptions(customer_id, reward_id, code) values (c.id, v_chosen.reward_id, v_code) returning id into v_red;
  end if;
  insert into wheel_spins(customer_id, slice_id, label, reward_id, redemption_id, free, cost_points, appointment_id)
  values (c.id, v_chosen.id, v_chosen.label, v_chosen.reward_id, v_red, v_free, v_paid, v_chair);
  select count(*) into v_idx from wheel_slices where active and (sort, id) < (v_chosen.sort, v_chosen.id);
  return jsonb_build_object('index', v_idx, 'slice_id', v_chosen.id, 'label', v_chosen.label, 'win', v_chosen.reward_id is not null, 'code', v_code, 'free', v_free, 'chair', v_chair is not null, 'paid', v_paid,
    'points', (select points from customers where id = c.id));
end $$;
-- تراجع: شغّل wheel_status و wheel_spin من patch_lucky_wheel.sql
