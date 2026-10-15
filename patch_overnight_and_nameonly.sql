-- patch_overnight_and_nameonly.sql
-- 1) ورديات بعد منتصف الليل (مثلاً 14:00 → 02:00)
-- 2) عميل بالاسم بس (من غير رقم) + ربطه برقم لاحقًا مع نقل النقاط
-- آمن للتشغيل أكتر من مرة. جرّبه على Branch الأول.

-- ===== 1) الورديات الليلية =====
-- الوردية اللي نهايتها <= بدايتها بتعدّي منتصف الليل:
-- يوم الوردية يغطي [البداية → 24:00) واليوم اللي بعده يغطي [00:00 → النهاية)
create or replace function public.barber_hours(p_day date)
returns table(barber_id uuid, is_off boolean, start_time time, end_time time)
language sql stable security definer set search_path to 'public' as $$
  select p.id,
    coalesce(s.is_off, false) or exists (select 1 from staff_leaves l where l.staff_id = p.id and p_day between l.from_date and l.to_date),
    coalesce(s.start_time, '00:00'::time),
    case when s.end_time is not null and s.end_time <= s.start_time then '23:59:59.999'::time
         else coalesce(s.end_time, '23:59'::time) end
  from profiles p left join staff_shifts s on s.staff_id = p.id and s.weekday = extract(dow from p_day)::int
  where p.role = 'barber' $$;

-- نهاية "ذيل" وردية امبارح اللي عدّت منتصف الليل (null لو مفيش)
create or replace function public.barber_spill(p_day date)
returns table(barber_id uuid, spill_end time)
language sql stable security definer set search_path to 'public' as $$
  select s.staff_id, s.end_time
  from staff_shifts s
  where s.weekday = extract(dow from (p_day - 1))::int
    and not s.is_off and s.end_time <= s.start_time and s.end_time > '00:00'::time
    and not exists (select 1 from staff_leaves l where l.staff_id = s.staff_id and (p_day - 1) between l.from_date and l.to_date) $$;

create or replace function public.guard_booking()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_l timestamp; h record; v_sp time; v_ok boolean;
begin
  if new.barber_id is null then return new; end if;
  v_l := new.starts_at at time zone my_tz();
  select * into h from barber_hours(v_l::date) b where b.barber_id = new.barber_id;
  if h.barber_id is null then return new; end if;
  select spill_end into v_sp from barber_spill(v_l::date) where barber_id = new.barber_id;
  v_ok := (not h.is_off and v_l::time >= h.start_time and v_l::time < h.end_time)
       or (v_sp is not null and v_l::time < v_sp);
  if not v_ok then raise exception 'الحلاق مش متاح في الميعاد ده'; end if;
  return new;
end $$;

create or replace function public.available_barbers(p_day date, p_period text)
returns table(id uuid, full_name text, waiting bigint, est_min bigint)
language sql stable security definer set search_path to 'public' as $$
  select b.barber_id, p.full_name,
    (select count(*) from appointments a where a.barber_id = b.barber_id and a.day = p_day and a.period = p_period and a.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments a join appointment_services x on x.appointment_id = a.id join services sv on sv.id = x.service_id
      where a.barber_id = b.barber_id and a.day = p_day and a.period = p_period and a.status in ('upcoming','checked_in','in_service')), 0)
  from barber_hours(p_day) b join profiles p on p.id = b.barber_id
       left join barber_spill(p_day) sp on sp.barber_id = b.barber_id, period_range(p_period) r
  where (not b.is_off and b.start_time < r.e and b.end_time > r.s)
     or (sp.spill_end is not null and sp.spill_end > r.s and '00:00'::time < r.e)
  order by 4 $$;

-- ===== 2) عميل بالاسم بس =====
create or replace function public.add_customer(p_name text, p_phone text default null)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_ph text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g'); v_n text := btrim(coalesce(p_name,'')); v_id bigint;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  if char_length(v_n) < 2 or char_length(v_n) > 60 then raise exception 'اكتب اسم العميل (من حرفين لـ 60 حرف)'; end if;
  if v_ph = '' then
    insert into customers(name, phone) values (v_n, null) returning id into v_id; return v_id;
  end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح (11 رقم ويبدأ بـ 01)'; end if;
  if exists (select 1 from customers c where c.phone = v_ph) then raise exception 'الرقم ده مسجل قبل كده'; end if;
  insert into customers(name, phone) values (v_n, v_ph) returning id into v_id;
  return v_id;
end $$;

-- ربط عميل (بالاسم بس) برقم موبايل.
-- لو الرقم مش مسجل: بيتحط على نفس السجل (النقاط والتاريخ زي ما هي).
-- لو الرقم مسجل لعميل تاني: بيتدمج السجل ده فيه (نقاط + زيارات + فواتير + حجوزات) وبيتمسح الاسم-بس.
-- بيرجّع id العميل النهائي.
create or replace function public.attach_customer_phone(p_customer bigint, p_phone text)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_ph text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g'); s customers; t customers;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح (11 رقم ويبدأ بـ 01)'; end if;
  select * into s from customers where id = p_customer for update;
  if s.id is null then raise exception 'العميل مش موجود'; end if;
  if coalesce(s.phone,'') <> '' then raise exception 'العميل ده عنده رقم بالفعل'; end if;
  select * into t from customers where phone = v_ph for update;
  if t.id is null then
    update customers set phone = v_ph where id = s.id;
    return s.id;
  end if;
  if s.user_id is not null and t.user_id is not null then raise exception 'الاتنين عندهم حسابات مختلفة - مينفعش دمج'; end if;
  update appointments set customer_id = t.id where customer_id = s.id;
  update invoices set customer_id = t.id where customer_id = s.id;
  update reviews set customer_id = t.id where customer_id = s.id;
  update loyalty_redemptions set customer_id = t.id where customer_id = s.id;
  update open_invoices set customer_id = t.id where customer_id = s.id;
  update loyalty_ledger set customer_id = t.id where customer_id = s.id;
  update customer_notifications set customer_id = t.id where customer_id = s.id;
  delete from claim_requests where customer_id = s.id;
  update customers set points = points + s.points, lifetime_points = lifetime_points + s.lifetime_points,
         visits = visits + s.visits, user_id = coalesce(user_id, s.user_id) where id = t.id;
  delete from customers where id = s.id;
  return t.id;
end $$;

revoke all on function public.attach_customer_phone(bigint,text) from public, anon;
grant execute on function public.attach_customer_phone(bigint,text) to authenticated;
revoke all on function public.barber_spill(date) from public, anon;
grant execute on function public.barber_spill(date) to authenticated;
