-- patch_hr_policy.sql — لائحة نظام العمل والحوافز والجزاءات (SALON ABO YOUSEF)
-- بيضيف: تقييم أسبوعي من 100، حافز 5% على الزيادة عن متوسط آخر 4 أسابيع (بتأثير التقييم)، مخالفات كبيرة بإجراء (سماع أقوال الحلاق + تأكيد المدير)،
-- ومتابعة التأخير (سماح 15 دقيقة، إنذار ← إنذار نهائي ← جزاء). أي خصم مالي بيتسجّل بتأكيد المدير/المالك بس ومرة واحدة لكل مخالفة.
-- مفيش حاجة بتتصرف أو بتتخصم أوتوماتيك من الملف ده. ولا بيغيّر غرامة التأخير الأوتوماتيكية الموجودة (late_fine_enabled): لو هتطبّق اللائحة
-- بدلها، اقفلها من الإعدادات ← الموظفين، عشان مايحصلش جزاءين عن نفس التأخير.
-- آمن لو اتشغّل أكتر من مرة.

create table if not exists public.hr_policy (
  id int primary key default 1 check (id = 1),
  incentive_pct numeric not null default 5 check (incentive_pct between 0 and 100),
  avg_weeks int not null default 4 check (avg_weeks between 1 and 12),
  grace_min int not null default 15 check (grace_min between 0 and 120),
  tiers jsonb not null default '[[90,100],[80,75],[70,50],[0,0]]'::jsonb,
  week_dow int not null default 6 check (week_dow between 0 and 6),   -- 6 = السبت بداية الأسبوع
  updated_at timestamptz not null default now()
);
insert into public.hr_policy(id) values (1) on conflict do nothing;

create table if not exists public.hr_evals (
  id bigint generated always as identity primary key,
  staff_id uuid not null,
  week_start date not null,
  quality int not null check (quality between 0 and 30),
  punctuality int not null check (punctuality between 0 and 25),
  hygiene int not null check (hygiene between 0 and 15),
  manner int not null check (manner between 0 and 20),
  coop int not null check (coop between 0 and 10),
  total int generated always as (quality + punctuality + hygiene + manner + coop) stored,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (staff_id, week_start)
);

create table if not exists public.hr_violations (
  id bigint generated always as identity primary key,
  staff_id uuid not null,
  day date not null,
  kind text not null check (kind in ('major', 'absence', 'conduct')),
  code text,
  details text not null,
  reply text,
  status text not null default 'open' check (status in ('open', 'confirmed', 'dismissed')),
  action text not null default 'none' check (action in ('none', 'warning', 'final_warning', 'penalty')),
  amount numeric not null default 0 check (amount >= 0),
  ded_id bigint,
  created_by uuid,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists hr_viol_staff_day on public.hr_violations(staff_id, day);

create table if not exists public.hr_incentive_paid (
  staff_id uuid not null,
  week_start date not null,
  amount numeric not null check (amount > 0),
  paid_by uuid,
  paid_at timestamptz not null default now(),
  primary key (staff_id, week_start)
);

alter table public.hr_policy enable row level security;
alter table public.hr_evals enable row level security;
alter table public.hr_violations enable row level security;
alter table public.hr_incentive_paid enable row level security;
revoke all on public.hr_policy, public.hr_evals, public.hr_violations, public.hr_incentive_paid from public, anon, authenticated;

create or replace function public.hr_week_start(p_d date) returns date language sql stable as $$
  select p_d - ((extract(dow from p_d)::int - (select week_dow from hr_policy where id = 1) + 7) % 7)
$$;

create or replace function public.hr_get() returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('policy', (select to_jsonb(p) from hr_policy p where id = 1),
    'week', hr_week_start((now() at time zone my_tz())::date),
    'barbers', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', full_name, 'pct', commission_pct) order by full_name) from profiles where role = 'barber'), '[]'::jsonb),
    'late_fine_on', coalesce(p11_cfg_bool('late_fine_enabled', true), true));
end $$;

create or replace function public.hr_policy_save(p jsonb) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'اللائحة للمالك بس'; end if;
  update hr_policy set
    incentive_pct = coalesce((p->>'incentive_pct')::numeric, incentive_pct),
    avg_weeks = coalesce((p->>'avg_weeks')::int, avg_weeks),
    grace_min = coalesce((p->>'grace_min')::int, grace_min),
    tiers = coalesce(p->'tiers', tiers), updated_at = now() where id = 1;
end $$;

-- التقييم الأسبوعي
create or replace function public.hr_eval_list(p_week date) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare ws date := hr_week_start(p_week);
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('staff_id', p.id, 'name', p.full_name, 'week', ws, 'eval', (select to_jsonb(e) - 'created_by' from hr_evals e where e.staff_id = p.id and e.week_start = ws)) order by p.full_name)
                     from profiles p where p.role = 'barber'), '[]'::jsonb);
end $$;

create or replace function public.hr_eval_save(p_staff uuid, p_week date, p_q int, p_p int, p_h int, p_m int, p_c int, p_note text default null)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare ws date := hr_week_start(p_week); v_tot int;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from profiles where id = p_staff and role = 'barber') then raise exception 'الموظف مش حلاق'; end if;
  if p_q not between 0 and 30 or p_p not between 0 and 25 or p_h not between 0 and 15 or p_m not between 0 and 20 or p_c not between 0 and 10 then
    raise exception 'الدرجات: الجودة 30، المواعيد 25، النظافة 15، التعامل 20، التعاون 10 كحد أقصى'; end if;
  insert into hr_evals(staff_id, week_start, quality, punctuality, hygiene, manner, coop, note, created_by)
    values (p_staff, ws, p_q, p_p, p_h, p_m, p_c, nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  on conflict (staff_id, week_start) do update set quality = excluded.quality, punctuality = excluded.punctuality, hygiene = excluded.hygiene,
    manner = excluded.manner, coop = excluded.coop, note = excluded.note, created_by = auth.uid()
  returning total into v_tot;
  return v_tot;
end $$;

-- حساب حافز حلاق في أسبوع
create or replace function public.hr_inc_row(p_staff uuid, p_week date) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare pol hr_policy; ws date := hr_week_start(p_week); v_tz text := my_tz(); v_created date; k int; wk date; v_c numeric; v_cur numeric; v_sum numeric := 0; v_n int := 0;
        v_avg numeric; v_inc numeric; v_base numeric; v_tot int; v_f numeric; v_canc boolean; v_final numeric := 0; v_paid numeric; v_st text; t jsonb; v_name text;
begin
  select * into pol from hr_policy where id = 1;
  select (created_at at time zone v_tz)::date, full_name into v_created, v_name from profiles where id = p_staff;
  select commission into v_cur from staff_summary(p_staff, (ws::timestamp at time zone v_tz), ((ws + 7)::timestamp at time zone v_tz));
  v_cur := coalesce(v_cur, 0);
  for k in 1..pol.avg_weeks loop
    wk := ws - 7 * k;
    continue when wk + 7 <= v_created;   -- أسبوع قبل ما يشتغل
    continue when exists (select 1 from hr_violations v where v.staff_id = p_staff and v.status = 'confirmed' and v.kind = 'absence' and v.day >= wk and v.day < wk + 7);   -- غياب غير مبرر
    select commission into v_c from staff_summary(p_staff, (wk::timestamp at time zone v_tz), ((wk + 7)::timestamp at time zone v_tz));
    v_sum := v_sum + coalesce(v_c, 0); v_n := v_n + 1;
  end loop;
  v_avg := case when v_n > 0 then round(v_sum / v_n, 2) end;
  v_inc := greatest(v_cur - coalesce(v_avg, v_cur), 0);
  v_base := round(v_inc * pol.incentive_pct / 100, 2);
  select total into v_tot from hr_evals where staff_id = p_staff and week_start = ws;
  if v_tot is not null then
    for t in select * from jsonb_array_elements(pol.tiers) loop
      if v_tot >= (t->>0)::numeric then v_f := (t->>1)::numeric; exit; end if;
    end loop;
  end if;
  v_canc := exists (select 1 from hr_violations v where v.staff_id = p_staff and v.status = 'confirmed' and v.kind = 'major' and v.day >= ws and v.day < ws + 7);
  select amount into v_paid from hr_incentive_paid where staff_id = p_staff and week_start = ws;
  if v_f is not null and not v_canc then v_final := round(v_base * v_f / 100, 2); end if;
  v_st := case when v_paid is not null then 'paid' when v_avg is null then 'no_baseline' when v_canc then 'cancelled' when v_tot is null then 'no_eval'
               when v_base = 0 then 'no_increase' when v_final = 0 then 'zero' else 'ready' end;
  return jsonb_build_object('staff_id', p_staff, 'name', v_name, 'week', ws, 'week_commission', v_cur, 'avg', v_avg, 'weeks_used', v_n, 'increase', v_inc,
    'base_incentive', v_base, 'eval_total', v_tot, 'factor', v_f, 'cancelled', v_canc, 'final', v_final, 'paid', v_paid, 'status', v_st);
end $$;
revoke all on function public.hr_inc_row(uuid, date) from public, anon, authenticated;

create or replace function public.hr_incentives(p_week date) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(hr_inc_row(p.id, p_week) order by p.full_name) from profiles p where p.role = 'barber'), '[]'::jsonb);
end $$;

create or replace function public.hr_incentive_pay(p_staff uuid, p_week date) returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb; v_amt numeric; ws date := hr_week_start(p_week);
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  r := hr_inc_row(p_staff, ws);
  if r->>'status' <> 'ready' then raise exception 'الحافز مش جاهز للصرف (الحالة: %)', r->>'status'; end if;
  v_amt := (r->>'final')::numeric;
  insert into hr_incentive_paid(staff_id, week_start, amount, paid_by) values (p_staff, ws, v_amt, auth.uid());
  perform staff_bonus_add(p_staff, v_amt, 'حافز أسبوعي (اللائحة) أسبوع ' || ws, false, null);
  return v_amt;
end $$;

-- المخالفات
create or replace function public.hr_violation_add(p_staff uuid, p_day date, p_kind text, p_code text, p_details text) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id bigint;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if btrim(coalesce(p_details, '')) = '' then raise exception 'اكتب وقائع المخالفة'; end if;
  insert into hr_violations(staff_id, day, kind, code, details, created_by) values (p_staff, coalesce(p_day, (now() at time zone my_tz())::date), p_kind, nullif(btrim(coalesce(p_code, '')), ''), btrim(p_details), auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- القرار: تأكيد (بعد سماع أقوال الحلاق) أو إلغاء. الخصم المالي مرة واحدة وبتأكيد صريح.
create or replace function public.hr_violation_decide(p_id bigint, p_confirm boolean, p_reply text, p_action text default 'none', p_amount numeric default 0)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v hr_violations; v_ded bigint;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select * into v from hr_violations where id = p_id for update;
  if not found then raise exception 'المخالفة مش موجودة'; end if;
  if v.status <> 'open' then raise exception 'المخالفة دي اتقرر فيها قبل كده'; end if;
  if not p_confirm then
    update hr_violations set status = 'dismissed', reply = nullif(btrim(coalesce(p_reply, '')), ''), decided_by = auth.uid(), decided_at = now() where id = p_id;
    return;
  end if;
  if btrim(coalesce(p_reply, '')) = '' then raise exception 'سجّل أقوال الحلاق الأول (اللائحة بتطلب سماع رده قبل التأكيد)'; end if;
  if p_action not in ('none', 'warning', 'final_warning', 'penalty') then raise exception 'إجراء غير صحيح'; end if;
  if p_action = 'penalty' then
    if coalesce(p_amount, 0) <= 0 then raise exception 'اكتب مبلغ الجزاء'; end if;
    insert into staff_transactions(staff_id, kind, amount, note, created_by) values (v.staff_id, 'deduction', p_amount, 'جزاء لائحة: ' || left(v.details, 80), auth.uid()) returning id into v_ded;
  end if;
  update hr_violations set status = 'confirmed', reply = btrim(p_reply), action = p_action, amount = case when p_action = 'penalty' then p_amount else 0 end,
         ded_id = v_ded, decided_by = auth.uid(), decided_at = now() where id = p_id;
end $$;

create or replace function public.hr_violation_list(p_from date, p_to date) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'staff_id', v.staff_id, 'name', p.full_name, 'day', v.day, 'kind', v.kind, 'code', v.code, 'details', v.details,
           'reply', v.reply, 'status', v.status, 'action', v.action, 'amount', v.amount) order by v.day desc, v.id desc)
           from hr_violations v left join profiles p on p.id = v.staff_id where v.day between p_from and p_to), '[]'::jsonb);
end $$;

-- التأخير الشهري: سماح (hr_policy.grace_min) ثم تدرّج: أول مرة إنذار، ثانية إنذار نهائي، ثالثة فأكتر جزاء بقرار الإدارة. السجل بيبدأ من جديد كل شهر.
create or replace function public.hr_late_status(p_month date default null) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_tz text := my_tz(); m0 date := date_trunc('month', coalesce(p_month, (now() at time zone my_tz())::date))::date; g int;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select grace_min into g from hr_policy where id = 1;
  return coalesce((select jsonb_agg(x order by (x->>'count')::int desc, x->>'name') from (
    select jsonb_build_object('staff_id', a.staff_id, 'name', p.full_name, 'count', count(*),
             'step', case when count(*) = 1 then 'warning' when count(*) = 2 then 'final_warning' else 'penalty' end,
             'days', jsonb_agg(jsonb_build_object('day', (a.check_in at time zone v_tz)::date, 'min', a.late_min) order by a.check_in)) x
      from attendance a join profiles p on p.id = a.staff_id
     where (a.check_in at time zone v_tz)::date >= m0 and (a.check_in at time zone v_tz)::date < (m0 + interval '1 month')::date and coalesce(a.late_min, 0) > g
     group by a.staff_id, p.full_name) q), '[]'::jsonb);
end $$;

do $$
declare f text;
begin
  foreach f in array array['hr_get()', 'hr_policy_save(jsonb)', 'hr_eval_list(date)', 'hr_eval_save(uuid,date,int,int,int,int,int,text)', 'hr_incentives(date)', 'hr_incentive_pay(uuid,date)',
                           'hr_violation_add(uuid,date,text,text,text)', 'hr_violation_decide(bigint,boolean,text,text,numeric)', 'hr_violation_list(date,date)', 'hr_late_status(date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
notify pgrst, 'reload schema';
