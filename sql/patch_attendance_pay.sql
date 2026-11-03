-- patch_attendance_pay.sql — الراتب الثابت ينزل بالحضور (بدل ما ينزل كل يوم من التقويم)
-- آمن للتكرار. مفيش مسح لأي حاجة قديمة: الأيام اللي فاتت بتفضل زي ما هي.

alter table staff_pay_profile add column if not exists att_from date;   -- من أنهي يوم الراتب بقى بالحضور
alter table staff_pay_profile add column if not exists att_to   date;   -- لو رجع للراتب الشهري

-- 1) سجل بداية الحضور تلقائيًا أول ما الموظف يتحول لـ "أجر يوم بالحضور"
create or replace function p19_pay_cutover() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_today date := (now() at time zone p11_tz())::date; v_start date;
begin
  if new.pay_mode = 'daily_attendance' and (tg_op = 'INSERT' or old.pay_mode is distinct from 'daily_attendance') then
    v_start := v_today;
    -- لو سجّل حضور النهارده قبل التحويل ومحدش نزّله يومية، النهارده يتحسب راتب عادي (يتسجل بكرة) فمتتحسبش مرتين
    if exists (select 1 from attendance a where a.staff_id = new.staff_id and (a.check_in at time zone p11_tz())::date = v_today)
       and not exists (select 1 from assistant_day_pay d where d.staff_id = new.staff_id and d.day = v_today) then
      v_start := v_today + 1;
    end if;
    new.att_from := coalesce(new.att_from, v_start);
    new.att_to := null;
  elsif tg_op = 'UPDATE' and old.pay_mode = 'daily_attendance' and new.pay_mode <> 'daily_attendance' and new.att_from is not null then
    new.att_to := greatest(v_today, new.att_from);
  end if;
  return new;
end $$;
drop trigger if exists trg_p19_pay_cutover on staff_pay_profile;
create trigger trg_p19_pay_cutover before insert or update of pay_mode on staff_pay_profile for each row execute function p19_pay_cutover();

-- اللي متحول فعلًا قبل الباتش ده: نبدأ من أول يوم اتسجلتله يومية (أو النهارده)
update staff_pay_profile pf set att_from = coalesce((select min(d.day) from assistant_day_pay d where d.staff_id = pf.staff_id), (now() at time zone p11_tz())::date)
 where pf.pay_mode = 'daily_attendance' and pf.att_from is null;

-- 2) راتب الفترة من غير أيام الحضور
create or replace function salary_part_for(p_staff uuid, p_salary numeric, p_from timestamptz, p_to timestamptz) returns numeric
language plpgsql stable security definer set search_path to 'public' as $$
declare pf record; a timestamptz; b timestamptz; r numeric := 0; tz text := my_tz();
begin
  select att_from, att_to into pf from staff_pay_profile where staff_id = p_staff;
  if not found or pf.att_from is null then return salary_part(p_salary, p_from, p_to); end if;
  a := pf.att_from::timestamp at time zone tz;
  b := case when pf.att_to is null then null else pf.att_to::timestamp at time zone tz end;
  if p_from < a then r := r + salary_part(p_salary, p_from, least(p_to, a)); end if;
  if b is not null and p_to > b then r := r + salary_part(p_salary, greatest(p_from, b), p_to); end if;
  return r;
end $$;
grant execute on function salary_part_for(uuid, numeric, timestamptz, timestamptz) to authenticated;

-- 3) تعديل الدوال اللي بتحسب الراتب (بنقرأ تعريفها من القاعدة ونبدّل جزء محدد، ولو الجزء مش موجود بيوقف)
do $$ declare d text; n text;
begin
  -- كشف الحساب
  d := pg_get_functiondef('staff_statement(uuid,timestamptz,timestamptz)'::regprocedure);
  if position('p19_att_skip' in d) = 0 then
    n := replace(d, 'where coalesce(pr.salary, 0) > 0 and (g.d at time zone tz) < v_to',
      'where coalesce(pr.salary, 0) > 0 and (g.d at time zone tz) < v_to /* p19_att_skip */
       and not exists (select 1 from staff_pay_profile pp where pp.staff_id = p_staff and pp.att_from is not null and g.d::date >= pp.att_from and (pp.att_to is null or g.d::date < pp.att_to))');
    if n = d then raise exception 'staff_statement: anchor not found'; end if;
    execute n;
  end if;
  -- ملخص الموظف
  d := pg_get_functiondef('staff_summary(uuid,timestamptz,timestamptz)'::regprocedure);
  if position('salary_part_for' in d) = 0 then
    n := replace(d, 'salary_part(v_sal, greatest(p_from, v_created), p_to)', 'salary_part_for(p_staff, v_sal, greatest(p_from, v_created), p_to)');
    if n = d then raise exception 'staff_summary: anchor not found'; end if;
    execute n;
  end if;
  -- التقارير
  d := pg_get_functiondef('report_data(timestamptz,timestamptz)'::regprocedure);
  if position('salary_part_for' in d) = 0 then
    n := replace(replace(d, 'sum(salary_part(pr.salary, p_from, p_to))', 'sum(salary_part_for(pr.id, pr.salary, p_from, p_to))'),
                 'salary_part(pr.salary, p_from, p_to) sal', 'salary_part_for(pr.id, pr.salary, p_from, p_to) sal');
    if n = d or position('salary_part(' in n) > 0 then raise exception 'report_data: anchor not found'; end if;
    execute n;
  end if;
  d := pg_get_functiondef('full_report(timestamptz,timestamptz)'::regprocedure);
  if position('salary_part_for' in d) = 0 then
    n := replace(d, 'round(salary_part(pr.salary, p_from, p_to), 2)', 'round(salary_part_for(pr.id, pr.salary, p_from, p_to), 2)');
    if n = d then raise exception 'full_report: anchor not found'; end if;
    execute n;
  end if;
  -- منع تكرار "أجر يوم": لو الأجر اليومي اتسجل بالفعل لنفس اليوم (من النظام القديم) مانسجلوش تاني
  d := pg_get_functiondef('p12_attendance_after_checkin()'::regprocedure);
  if position('p19_dedupe' in d) = 0 then
    n := replace(d, E'      insert into staff_transactions(staff_id, kind, amount, note)\n      values (NEW.staff_id, ''bonus'', pf.daily_wage, ''أجر يوم '' || v_day) returning id into v_tx;',
      E'      select id into v_tx from staff_transactions where staff_id = NEW.staff_id and kind = ''bonus'' and note = ''أجر يوم '' || v_day order by id limit 1; /* p19_dedupe */\n      if v_tx is null then\n        insert into staff_transactions(staff_id, kind, amount, note)\n        values (NEW.staff_id, ''bonus'', pf.daily_wage, ''أجر يوم '' || v_day) returning id into v_tx;\n      end if;');
    if n = d then raise exception 'p12_attendance_after_checkin: anchor not found'; end if;
    execute n;
  end if;
  -- دقايق التأخير لما الإدارة تسجّل حضور بإيدها: سماح 600 (خصم الدقيقة) مش بيتخصم من الدقايق
  d := pg_get_functiondef('att_calc_late(uuid,timestamptz)'::regprocedure);
  if position('p19_grace' in d) = 0 then
    n := replace(d, '- coalesce(v_grace, 0), 0)', '- (case when coalesce(v_grace, 0) >= 600 then 0 else coalesce(v_grace, 0) end /* p19_grace */), 0)');
    if n = d then raise exception 'att_calc_late: anchor not found'; end if;
    execute n;
  end if;
end $$;

-- 4) زرار "حوّل كل أصحاب الراتب الثابت للحضور" (للمالك فقط)
-- اليومية = اليومية المسجلة، ولو مفيش = الراتب ÷ 30. المدير والمالك مش بيدخلوا.
create or replace function att_pay_all() returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; w numeric; out jsonb := '[]'::jsonb;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  for r in select p.id, p.full_name, p.salary, coalesce(pf.daily_wage,0) dw, coalesce(pf.standard_hours,12) hrs
             from profiles p left join staff_pay_profile pf on pf.staff_id = p.id
            where p.role::text in ('assistant','barber','cashier') and coalesce(p.salary,0) > 0
              and coalesce(pf.pay_mode,'monthly') <> 'daily_attendance' order by p.full_name loop
    w := case when r.dw > 0 then r.dw else round(r.salary / 30, 2) end;
    perform set_daily_pay(r.id, w, r.hrs, 600, true);
    insert into late_rule(staff_id, method, updated_at) values (r.id, 'flat', now())
      on conflict (staff_id) do update set method = 'flat', updated_at = now();
    out := out || jsonb_build_object('id', r.id, 'name', r.full_name, 'daily_wage', w);
  end loop;
  return out;
end $$;
grant execute on function att_pay_all() to authenticated;
