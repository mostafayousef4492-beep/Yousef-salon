-- patch_lucky_wheel.sql — عجلة الحظ في تطبيق العملاء
-- الجايزة = كود في loyalty_redemptions (نفس نظام استبدال النقاط) والكاشير بيطبّقه من pos_checkout زي أي كود. مفيش منطق خصم جديد.
-- لفة مجانية بحد تتحكم فيه، وبعدها بنقاط. كل القيم من الإعدادات، والعجلة موقوفة (wheel_on=false) لحد ما تشغّلها.
-- آمن للتشغيل أكتر من مرة.

create table if not exists public.wheel_slices(
  id bigserial primary key,
  label text not null,
  reward_id bigint references public.loyalty_rewards(id) on delete restrict,  -- null = حظ أوفر (من غير جايزة)
  weight int not null default 1 check (weight >= 0),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.wheel_spins(
  id bigserial primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  slice_id bigint references public.wheel_slices(id) on delete set null,
  label text,
  reward_id bigint,
  redemption_id bigint,
  free boolean not null default false,
  cost_points int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists wheel_spins_cust_idx on public.wheel_spins(customer_id, created_at desc);

alter table public.wheel_slices enable row level security;
alter table public.wheel_spins enable row level security;
drop policy if exists "wheel slices mgr" on public.wheel_slices;
create policy "wheel slices mgr" on public.wheel_slices for all using (is_mgr()) with check (is_mgr());
drop policy if exists "wheel spins mgr read" on public.wheel_spins;
create policy "wheel spins mgr read" on public.wheel_spins for select using (is_mgr());
-- العميل بيتعامل مع العجلة من الدوال بس (security definer)

-- الإعدادات (بتظهر في الإعدادات ضمن "الولاء")
insert into public.rule_defs(key, grp, label, hint, kind, min, max, def, danger, kw, sort) values
 ('wheel_on','الولاء','عجلة الحظ شغّالة','موقوفة افتراضيًا. شغّلها بعد ما تظبط القطاعات من شاشة عجلة الحظ','bool',null,null,'false',false,'عجلة حظ wheel لفة جوايز',120),
 ('wheel_cost','الولاء','تكلفة اللفة (نقاط)','اللفة الأولى المجانية بعدها بنقاط. صفر = كل اللفات مجانية (بالحد اليومي)','num',0,100000,'50',true,'عجلة حظ wheel نقاط',121),
 ('wheel_free_days','الولاء','كل كام يوم لفة مجانية','صفر = مرة واحدة بس في العمر لكل عميل','num',0,3650,'0',false,'عجلة حظ wheel مجانية',122),
 ('wheel_daily_max','الولاء','أقصى لفات في اليوم للعميل','بيشمل المجانية والمدفوعة','num',1,100,'3',false,'عجلة حظ wheel حد يومي',123),
 ('wheel_month_prizes','الولاء','أقصى جوايز في الشهر (للصالون كله)','لما يخلص العدد العجلة بتدّي "حظ أوفر". صفر = من غير حد (مش مفضّل)','num',0,100000,'30',true,'عجلة حظ wheel سقف جوايز',124)
on conflict (key) do nothing;

-- قطاعات مبدئية (موقوفة لحد ما تشغّل العجلة). عدّلها من شاشة عجلة الحظ.
insert into public.wheel_slices(label, reward_id, weight, sort)
select x.label, x.rid, x.w, x.s from (values
  ('حظ أوفر', null::bigint, 60, 1),
  ('خصم 20 جنيه', (select id from public.loyalty_rewards where active and kind='amount' and value=20 order by id limit 1), 25, 2),
  ('خصم 10%', (select id from public.loyalty_rewards where active and kind='pct' and value=10 order by id limit 1), 15, 3)
) x(label, rid, w, s)
where not exists (select 1 from public.wheel_slices);

-- حالة العجلة للعميل (من غير الأوزان)
create or replace function public.wheel_status()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c customers; v_on boolean := p11_cfg_bool('wheel_on', false); v_days int := p_ref_cfg('wheel_free_days',0)::int; v_cost int := p_ref_cfg('wheel_cost',50)::int;
        v_max int := p_ref_cfg('wheel_daily_max',3)::int; v_free boolean; v_today int; v_last timestamptz;
begin
  select * into c from customers where user_id = auth.uid();
  if not found then return jsonb_build_object('on', false); end if;
  if not v_on then return jsonb_build_object('on', false); end if;
  select max(created_at) into v_last from wheel_spins where customer_id = c.id and free;
  v_free := v_last is null or (v_days > 0 and v_last < now() - make_interval(days => v_days));
  select count(*) into v_today from wheel_spins where customer_id = c.id and created_at > now() - interval '1 day';
  return jsonb_build_object('on', true, 'free', v_free, 'cost', v_cost, 'points', c.points,
    'left_today', greatest(v_max - v_today, 0),
    'slices', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'label', label, 'win', reward_id is not null) order by sort, id), '[]'::jsonb) from wheel_slices where active));
end $$;

-- اللفّ: النتيجة بتتحدد هنا في السيرفر
create or replace function public.wheel_spin()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c customers; v_days int := p_ref_cfg('wheel_free_days',0)::int; v_cost int := p_ref_cfg('wheel_cost',50)::int; v_max int := p_ref_cfg('wheel_daily_max',3)::int;
        v_cap int := p_ref_cfg('wheel_month_prizes',30)::int; v_last timestamptz; v_free boolean; v_today int; v_tot int; v_pick int; v_acc int := 0;
        s wheel_slices; v_chosen wheel_slices; v_cur numeric; v_code text; v_red bigint; v_month int; v_idx int := 0; v_i int := 0; v_paid int := 0;
begin
  if not p11_cfg_bool('wheel_on', false) then raise exception 'عجلة الحظ مش شغّالة دلوقتي'; end if;
  select * into c from customers where user_id = auth.uid() for update;
  if not found then raise exception 'سجّل دخول الأول'; end if;
  select count(*) into v_today from wheel_spins where customer_id = c.id and created_at > now() - interval '1 day';
  if v_today >= v_max then raise exception 'وصلت للحد الأقصى من اللفات النهارده، جرّب بكرة'; end if;
  select max(created_at) into v_last from wheel_spins where customer_id = c.id and free;
  v_free := v_last is null or (v_days > 0 and v_last < now() - make_interval(days => v_days));
  if not v_free and v_cost > 0 then
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
  insert into wheel_spins(customer_id, slice_id, label, reward_id, redemption_id, free, cost_points)
  values (c.id, v_chosen.id, v_chosen.label, v_chosen.reward_id, v_red, v_free, v_paid);
  select count(*) into v_idx from wheel_slices where active and (sort, id) < (v_chosen.sort, v_chosen.id);
  return jsonb_build_object('index', v_idx, 'slice_id', v_chosen.id, 'label', v_chosen.label, 'win', v_chosen.reward_id is not null, 'code', v_code, 'free', v_free, 'paid', v_paid,
    'points', (select points from customers where id = c.id));
end $$;

-- تقرير للمدير
create or replace function public.wheel_report(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not coalesce(is_mgr(), false) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'spins', (select count(*) from wheel_spins where created_at > now() - make_interval(days => p_days)),
    'free_spins', (select count(*) from wheel_spins where free and created_at > now() - make_interval(days => p_days)),
    'prizes', (select count(*) from wheel_spins where redemption_id is not null and created_at > now() - make_interval(days => p_days)),
    'points_collected', (select coalesce(sum(cost_points),0) from wheel_spins where created_at > now() - make_interval(days => p_days)),
    'by_label', (select coalesce(jsonb_agg(jsonb_build_object('label', label, 'n', n) order by n desc), '[]'::jsonb) from (select label, count(*) n from wheel_spins where created_at > now() - make_interval(days => p_days) group by label) q));
end $$;

revoke all on function public.wheel_status(), public.wheel_spin(), public.wheel_report(int) from public, anon;
grant execute on function public.wheel_status(), public.wheel_spin(), public.wheel_report(int) to authenticated;
-- تراجع: drop function wheel_status(), wheel_spin(), wheel_report(int); drop table wheel_spins, wheel_slices; delete from rule_defs where key like 'wheel_%';
