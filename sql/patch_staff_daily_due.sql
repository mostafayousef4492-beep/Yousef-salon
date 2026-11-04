-- تقرير "مستحق الحلاقين يوم بيوم": لكل يوم (يوم عمل مسجّل أو تاريخ عادي قبل نظام يوم العمل) ولكل موظف: العمولة + المكافآت + الراتب (لو فيه) − السحب − الخصومات = المستحق.
-- بيستخدم staff_summary نفسها (نفس أرقام حساب الموظف) على نافذة كل يوم عمل. للمدير/المالك بس. آمن للتشغيل أكتر من مرة.
create or replace function public.staff_daily_due(p_from date, p_to date) returns table(
  day date, staff_id uuid, name text, role text, cuts bigint, sales numeric, commission numeric, bonuses numeric,
  advances numeric, deductions numeric, salary numeric, net numeric)
language plpgsql stable security definer set search_path = public as $$
declare d record; s record; r record;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'راجع التاريخ'; end if;
  if p_to - p_from > 62 then raise exception 'الفترة أطول من 62 يوم'; end if;
  -- كل يوم في الفترة: لو ليه يوم عمل مسجّل بنستخدم نافذته، ولو لأ (أيام قبل ما نظام يوم العمل يشتغل) بنستخدم اليوم من 12 منتصف الليل
  for d in
    select g::date as day,
           case when b.day is not null then p24b_start(b.day) else (g::date::timestamp at time zone my_tz()) end as s0,
           case when b.day is not null then coalesce(b.closed_at, now())
                else least(((g::date + 1)::timestamp at time zone my_tz()),
                           coalesce((select min(p24b_start(b2.day)) from business_days b2 where b2.day > g::date), 'infinity'::timestamptz)) end as e0
      from generate_series(p_from, p_to, interval '1 day') g
      left join business_days b on b.day = g::date
     order by g loop
    for s in select p.id, p.full_name, p.role::text as role from profiles p where p.role::text in ('barber', 'assistant') order by (p.role::text = 'barber') desc, p.full_name loop
      select * into r from staff_summary(s.id, d.s0, d.e0) limit 1;
      day := d.day; staff_id := s.id; name := s.full_name; role := s.role;
      cuts := coalesce(r.cuts, 0); sales := coalesce(r.sales, 0); commission := coalesce(r.commission, 0);
      bonuses := coalesce(r.bonuses, 0); advances := coalesce(r.advances, 0); deductions := coalesce(r.deductions, 0);
      salary := coalesce(r.salary, 0); net := coalesce(r.net, 0);
      if cuts <> 0 or sales <> 0 or commission <> 0 or bonuses <> 0 or advances <> 0 or deductions <> 0 or salary <> 0 or net <> 0 then return next; end if;
    end loop;
  end loop;
end $$;
revoke all on function public.staff_daily_due(date, date) from public, anon;
grant execute on function public.staff_daily_due(date, date) to authenticated;
