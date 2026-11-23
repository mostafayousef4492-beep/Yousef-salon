-- patch_staff_wheel.sql — عجلة تحديات الموظفين (غير عجلة تحدي العملاء)
-- تحديات المحل: المساعد للنضافة والتجهيز، والصنايعي للشغل. إنت اللي بتحددها وبتحدد الجوايز من الإعدادات.
-- الدورة: الموظف بيدوس «خلّصت» ← المدير أو الكاشير بيأكّد (مش نفس الشخص) ← الموظف يلفّ العجلة ← جايزة.
-- الجايزة: فلوس صغيرة (بتتسجل «مكافأة» في حساب الموظف وبتتصرف مع الراتب، مابتلمسش الدرج) أو نقاط موظف بتتبدّل بجوايز من كتالوج إنت بتحدده.
-- مفيش خصم ولا غرامة خالص. موقوفة (staff_wheel_on=false) لحد ما تشغّلها. آمن للتشغيل أكتر من مرة. مفيش بيانات حالية بتتغير.

create table if not exists public.staff_ch_defs(
  id bigserial primary key,
  title text not null,
  role text not null default 'all' check (role in ('all','barber','assistant')),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.staff_ch_log(
  id bigserial primary key,
  def_id bigint references public.staff_ch_defs(id) on delete set null,
  staff_id uuid not null,
  title text not null,
  day date not null,
  status text not null default 'claimed' check (status in ('claimed','confirmed','rejected','spun')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz,
  prize_label text, prize_kind text, prize_value numeric not null default 0, spun_at timestamptz
);
create unique index if not exists staff_ch_log_once on public.staff_ch_log(def_id, staff_id, day);
create index if not exists staff_ch_log_status on public.staff_ch_log(status, day);
create table if not exists public.staff_wheel_slices(
  id bigserial primary key,
  label text not null,
  kind text not null default 'points' check (kind in ('cash','points','none')),
  value numeric not null default 0 check (value >= 0),
  weight int not null default 1 check (weight >= 0),
  active boolean not null default true,
  sort int not null default 0
);
create table if not exists public.staff_points_ledger(
  id bigserial primary key,
  staff_id uuid not null,
  pts int not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create index if not exists staff_points_ledger_idx on public.staff_points_ledger(staff_id);
create table if not exists public.staff_rewards(
  id bigserial primary key,
  label text not null,
  cost int not null default 100 check (cost > 0),
  active boolean not null default true
);
create table if not exists public.staff_redeems(
  id bigserial primary key,
  staff_id uuid not null,
  reward_id bigint references public.staff_rewards(id) on delete set null,
  label text not null,
  cost int not null,
  status text not null default 'pending' check (status in ('pending','done','rejected')),
  created_at timestamptz not null default now(),
  resolved_by uuid, resolved_at timestamptz
);

alter table public.staff_ch_defs enable row level security;
alter table public.staff_ch_log enable row level security;
alter table public.staff_wheel_slices enable row level security;
alter table public.staff_points_ledger enable row level security;
alter table public.staff_rewards enable row level security;
alter table public.staff_redeems enable row level security;
do $$ declare t text; begin
  foreach t in array array['staff_ch_defs','staff_wheel_slices','staff_rewards'] loop
    execute format('drop policy if exists "%1$s mgr" on public.%1$s', t);
    execute format('create policy "%1$s mgr" on public.%1$s for all using (coalesce(is_mgr(),false)) with check (coalesce(is_mgr(),false))', t);
  end loop;
  foreach t in array array['staff_ch_log','staff_points_ledger','staff_redeems'] loop
    execute format('drop policy if exists "%1$s mgr read" on public.%1$s', t);
    execute format('create policy "%1$s mgr read" on public.%1$s for select using (coalesce(is_mgr(),false))', t);
  end loop;
end $$;
-- الموظف والكاشير بيتعاملوا من الدوال بس (security definer)

insert into public.rule_defs(key, grp, label, hint, kind, min, max, def, danger, kw, sort) values
 ('staff_wheel_on','الولاء','عجلة تحديات الموظفين شغّالة','موقوفة افتراضيًا. تحديات النضافة والشغل للموظفين، والجوايز من شاشة عجلة الموظفين','bool',null,null,'false',false,'موظفين تحديات staff عجلة',140),
 ('staff_wheel_day_max','الولاء','أقصى لفات للموظف في اليوم','حتى لو خلّص تحديات كتير','num',1,10,'2',false,'موظفين staff حد يومي لفات',141),
 ('staff_wheel_cash_month','الولاء','أقصى فلوس جوايز العجلة في الشهر (للمحل كله، جنيه)','لما يخلص الرقم، قطاع الفلوس بيبقى «حظ أوفر». صفر = مفيش فلوس خالص','num',0,1000000,'500',true,'موظفين staff فلوس سقف مكافأة',142)
on conflict (key) do nothing;

-- تحديات مبدئية (عدّلها أو امسحها من شاشة عجلة الموظفين)
insert into public.staff_ch_defs(title, role, sort)
select * from (values
 ('الكراسي والمرايات نضيفة قبل أول عميل','assistant',1),
 ('الأدوات متعقّمة ومترتبة بعد كل عميل','assistant',2),
 ('الأرضية من غير شعر طول اليوم','assistant',3),
 ('٦ عملاء في اليوم من غير شكوى','barber',4),
 ('كل مواعيد اليوم في ميعادها','barber',5),
 ('عميل جاب صاحبه النهارده','barber',6)
) v(t,r,s) where not exists (select 1 from public.staff_ch_defs);
insert into public.staff_wheel_slices(label, kind, value, weight, sort)
select * from (values
 ('10 جنيه','cash',10,2,1),
 ('20 جنيه','cash',20,1,2),
 ('10 نقاط','points',10,4,3),
 ('25 نقطة','points',25,2,4),
 ('حظ أوفر','none',0,3,5)
) v(l,k,v,w,s) where not exists (select 1 from public.staff_wheel_slices);
insert into public.staff_rewards(label, cost)
select * from (values ('ساعة إجازة',100),('وجبة على المحل',150),('يوم إجازة',500)) v(l,c)
where not exists (select 1 from public.staff_rewards);

create or replace function public.p_sw_day() returns date language sql stable security definer set search_path to 'public' as $$
  select (now() at time zone my_tz())::date $$;
revoke all on function public.p_sw_day() from public, anon, authenticated;

create or replace function public.p_sw_pts(p_staff uuid) returns int language sql stable security definer set search_path to 'public' as $$
  select coalesce(sum(pts),0)::int from staff_points_ledger where staff_id = p_staff $$;
revoke all on function public.p_sw_pts(uuid) from public, anon, authenticated;

-- شاشة الموظف: تحدياته النهارده + نقاطه + الجوايز
create or replace function public.staff_ch_me() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_role text; v_day date := p_sw_day(); v_left int; v_max int := p_ref_cfg('staff_wheel_day_max',2)::int;
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  select role::text into v_role from profiles where id = auth.uid();
  if v_role is null or v_role = 'customer' then raise exception 'غير مصرح'; end if;
  v_left := greatest(0, v_max - (select count(*) from staff_ch_log where staff_id = auth.uid() and day = v_day and status = 'spun'));
  return jsonb_build_object(
    'on', p11_cfg_bool('staff_wheel_on', false), 'role', v_role, 'points', p_sw_pts(auth.uid()), 'spins_left', v_left,
    'list', coalesce((select jsonb_agg(jsonb_build_object('def_id', d.id, 'title', d.title, 'log_id', l.id, 'status', l.status, 'prize', l.prize_label) order by d.sort, d.id)
       from staff_ch_defs d left join staff_ch_log l on l.def_id = d.id and l.staff_id = auth.uid() and l.day = v_day
       where d.active and (d.role = 'all' or d.role = v_role)), '[]'::jsonb),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', label, 'cost', cost) order by cost) from staff_rewards where active), '[]'::jsonb),
    'redeems', coalesce((select jsonb_agg(jsonb_build_object('label', label, 'cost', cost, 'status', status) order by id desc) from (select * from staff_redeems where staff_id = auth.uid() order by id desc limit 5) r), '[]'::jsonb),
    'slices', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'label', label, 'kind', kind) order by sort, id) from staff_wheel_slices where active), '[]'::jsonb));
end $$;

create or replace function public.staff_ch_claim(p_def bigint) returns bigint
language plpgsql security definer set search_path to 'public' as $$
declare v_role text; d staff_ch_defs; v_id bigint;
begin
  if not p11_cfg_bool('staff_wheel_on', false) then raise exception 'عجلة الموظفين مش شغّالة دلوقتي'; end if;
  select role::text into v_role from profiles where id = auth.uid();
  if v_role is null or v_role = 'customer' then raise exception 'غير مصرح'; end if;
  select * into d from staff_ch_defs where id = p_def and active;
  if not found or not (d.role = 'all' or d.role = v_role) then raise exception 'التحدي ده مش ليك'; end if;
  insert into staff_ch_log(def_id, staff_id, title, day) values (d.id, auth.uid(), d.title, p_sw_day())
    on conflict (def_id, staff_id, day) do nothing returning id into v_id;
  if v_id is null then raise exception 'سجّلت التحدي ده النهارده قبل كده'; end if;
  return v_id;
end $$;

-- للمدير أو الكاشير: التحديات المستنية تأكيد النهارده
create or replace function public.staff_ch_pending() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
begin
  if not (coalesce(is_mgr(), false) or coalesce(can_use_pos(), false)) then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'staff', coalesce(p.full_name, 'موظف'), 'role', p.role::text, 'title', l.title, 'at', l.created_at) order by l.created_at)
    from staff_ch_log l left join profiles p on p.id = l.staff_id
    where l.status = 'claimed' and l.day >= p_sw_day() - 1 and l.staff_id <> auth.uid()), '[]'::jsonb);
end $$;

create or replace function public.staff_ch_decide(p_log bigint, p_ok boolean) returns void
language plpgsql security definer set search_path to 'public' as $$
declare l staff_ch_log;
begin
  if not (coalesce(is_mgr(), false) or coalesce(can_use_pos(), false)) then raise exception 'غير مصرح'; end if;
  select * into l from staff_ch_log where id = p_log for update;
  if not found or l.status <> 'claimed' then raise exception 'التحدي ده اتراجع قبل كده'; end if;
  if l.staff_id = auth.uid() then raise exception 'مينفعش تأكّد تحدي بتاعك'; end if;
  update staff_ch_log set status = case when p_ok then 'confirmed' else 'rejected' end, decided_by = auth.uid(), decided_at = now() where id = p_log;
end $$;

create or replace function public.staff_ch_spin(p_log bigint) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare l staff_ch_log; s staff_wheel_slices; v_tot int; v_pick int; v_acc int := 0; v_day date := p_sw_day();
        v_max int := p_ref_cfg('staff_wheel_day_max',2)::int; v_cap numeric := p_ref_cfg('staff_wheel_cash_month',500);
        v_month numeric; v_label text; v_kind text; v_val numeric; v_sid bigint;
begin
  if not p11_cfg_bool('staff_wheel_on', false) then raise exception 'عجلة الموظفين مش شغّالة دلوقتي'; end if;
  select * into l from staff_ch_log where id = p_log for update;
  if not found or l.staff_id <> auth.uid() then raise exception 'غير مصرح'; end if;
  if l.status <> 'confirmed' then raise exception 'لازم المدير أو الكاشير يأكّد التحدي الأول'; end if;
  if (select count(*) from staff_ch_log where staff_id = auth.uid() and day = v_day and status = 'spun') >= v_max then raise exception 'خلّصت لفات النهارده'; end if;
  select coalesce(sum(weight),0) into v_tot from staff_wheel_slices where active and weight > 0;
  if v_tot <= 0 then raise exception 'العجلة مفيهاش جوايز، كلّم المدير'; end if;
  v_pick := floor(random() * v_tot)::int;
  for s in select * from staff_wheel_slices where active and weight > 0 order by sort, id loop
    v_acc := v_acc + s.weight;
    if v_pick < v_acc then exit; end if;
  end loop;
  v_label := s.label; v_kind := s.kind; v_val := s.value; v_sid := s.id;
  if v_kind = 'cash' then
    select coalesce(sum(prize_value),0) into v_month from staff_ch_log where prize_kind = 'cash' and spun_at >= date_trunc('month', now() at time zone my_tz()) at time zone my_tz();
    if v_val <= 0 or v_month + v_val > v_cap then v_kind := 'none'; v_val := 0; v_label := 'حظ أوفر'; v_sid := coalesce((select id from staff_wheel_slices where active and kind = 'none' order by sort, id limit 1), s.id); end if;
  end if;
  if v_kind = 'cash' then
    insert into staff_transactions(staff_id, kind, amount, note, created_by) values (auth.uid(), 'bonus', round(v_val,2), 'جايزة عجلة تحديات الموظفين: ' || l.title, auth.uid());
  elsif v_kind = 'points' and v_val > 0 then
    insert into staff_points_ledger(staff_id, pts, reason) values (auth.uid(), v_val::int, 'عجلة التحديات: ' || l.title);
  end if;
  update staff_ch_log set status = 'spun', prize_label = v_label, prize_kind = v_kind, prize_value = v_val, spun_at = now() where id = l.id;
  return jsonb_build_object('label', v_label, 'kind', v_kind, 'value', v_val, 'points', p_sw_pts(auth.uid()), 'slice_id', v_sid);
end $$;

create or replace function public.staff_reward_redeem(p_reward bigint) returns void
language plpgsql security definer set search_path to 'public' as $$
declare r staff_rewards;
begin
  if not p11_cfg_bool('staff_wheel_on', false) then raise exception 'عجلة الموظفين مش شغّالة دلوقتي'; end if;
  if (select role::text from profiles where id = auth.uid()) in ('customer') or auth.uid() is null then raise exception 'غير مصرح'; end if;
  select * into r from staff_rewards where id = p_reward and active;
  if not found then raise exception 'الجايزة مش متاحة'; end if;
  perform pg_advisory_xact_lock(hashtext('swp' || auth.uid()::text));
  if p_sw_pts(auth.uid()) < r.cost then raise exception 'نقاطك مش كفاية'; end if;
  insert into staff_points_ledger(staff_id, pts, reason) values (auth.uid(), -r.cost, 'استبدال: ' || r.label);
  insert into staff_redeems(staff_id, reward_id, label, cost) values (auth.uid(), r.id, r.label, r.cost);
end $$;

create or replace function public.staff_redeem_resolve(p_id bigint, p_ok boolean) returns void
language plpgsql security definer set search_path to 'public' as $$
declare r staff_redeems;
begin
  if not coalesce(is_mgr(), false) then raise exception 'غير مصرح'; end if;
  select * into r from staff_redeems where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'الطلب ده اتراجع قبل كده'; end if;
  update staff_redeems set status = case when p_ok then 'done' else 'rejected' end, resolved_by = auth.uid(), resolved_at = now() where id = p_id;
  if not p_ok then insert into staff_points_ledger(staff_id, pts, reason) values (r.staff_id, r.cost, 'رجوع نقاط: ' || r.label); end if;
end $$;

create or replace function public.staff_ch_report(p_days int default 30) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_since date := p_sw_day() - greatest(1, least(coalesce(p_days,30), 365));
begin
  if not coalesce(is_mgr(), false) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'done', (select count(*) from staff_ch_log where day >= v_since and status in ('confirmed','spun')),
    'rejected', (select count(*) from staff_ch_log where day >= v_since and status = 'rejected'),
    'cash', (select coalesce(sum(prize_value),0) from staff_ch_log where day >= v_since and prize_kind = 'cash'),
    'points', (select coalesce(sum(prize_value),0) from staff_ch_log where day >= v_since and prize_kind = 'points'),
    'by_staff', coalesce((select jsonb_agg(x order by (x->>'done')::int desc) from (select jsonb_build_object('name', coalesce(p.full_name,'موظف'), 'done', count(*) filter (where l.status in ('confirmed','spun'))) x
        from staff_ch_log l left join profiles p on p.id = l.staff_id where l.day >= v_since group by p.id, p.full_name) q), '[]'::jsonb),
    'redeems', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'staff', coalesce(p.full_name,'موظف'), 'label', r.label, 'cost', r.cost) order by r.id)
        from staff_redeems r left join profiles p on p.id = r.staff_id where r.status = 'pending'), '[]'::jsonb));
end $$;

do $$ declare f text; begin
  foreach f in array array['staff_ch_me()','staff_ch_claim(bigint)','staff_ch_pending()','staff_ch_decide(bigint,boolean)','staff_ch_spin(bigint)','staff_reward_redeem(bigint)','staff_redeem_resolve(bigint,boolean)','staff_ch_report(int)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
-- تراجع: drop function staff_ch_me(), staff_ch_claim(bigint), staff_ch_pending(), staff_ch_decide(bigint,boolean), staff_ch_spin(bigint), staff_reward_redeem(bigint), staff_redeem_resolve(bigint,boolean), staff_ch_report(int), p_sw_day(), p_sw_pts(uuid); drop table staff_redeems, staff_rewards, staff_points_ledger, staff_wheel_slices, staff_ch_log, staff_ch_defs; delete from rule_defs where key like 'staff_wheel_%';
