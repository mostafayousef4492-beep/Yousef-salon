-- ترحيل الحجوزات اللي ماتخدمتش لتاني يوم، وتبقى أول ناس في الدور.
-- بيحصل تلقائي لما تفتح يوم جديد (open_business_day): أي تذكرة لسه "قادمة" أو "وصل" من آخر ٣ أيام
-- بتتنقل لليوم الجديد بنفس الحلاق، بترتيبها الأصلي، وقبل أي حجز تاني في اليوم ده.
-- الزبون بيتبعتله إشعار، ولما الحلاق يسجّل حضوره بيتبعتله إشعار تاني "تعالى".
-- مفيش بيانات بتتمسح. التراجع: drop function p31_carry_over(date); drop trigger zz_p31_attendance_checkin on attendance;
--   وارجع open_business_day / p15_appt_guard / p11_appt_after_change للنسخ القديمة (من باتشات الريبو).

alter table public.appointments add column if not exists carried_from date;

-- الحارس: يسمح بإرجاع "وصل" لـ"قادمة" وقت الترحيل بس
create or replace function public.p15_appt_guard() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare o text := OLD.status::text; n text := NEW.status::text; ok boolean;
begin
  if n = o then return NEW; end if;
  if coalesce(current_setting('p31.carry', true), '') = '1' and o = 'checked_in' and n = 'upcoming' then return NEW; end if;
  ok := case o
    when 'upcoming'   then n in ('checked_in', 'cancelled', 'no_show')
    when 'checked_in' then n in ('in_service', 'done', 'cancelled', 'no_show')
    when 'in_service' then n in ('done', 'cancelled')
    when 'no_show'    then n = 'upcoming' and coalesce(current_setting('p15.return', true), '') = '1'
    else false end;
  if not ok then
    raise exception 'انتقال غير مسموح للتذكرة: % ← %', o, n using errcode = 'check_violation';
  end if;
  if n = 'checked_in' and NEW.present_at is null then NEW.present_at := now(); end if;
  return NEW;
end $$;

-- ماتبعتش "اقترب دورك" وقت الترحيل
create or replace function public.p11_appt_after_change() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if coalesce(current_setting('p31.carry', true), '') = '1' then return NEW; end if;
  begin
    if TG_OP = 'INSERT' then
      perform p11_notify_near_turn(NEW.day, NEW.period::text);
    else
      if NEW.status is distinct from OLD.status then
        if NEW.status::text = 'done' then perform p11_learn(NEW.id); end if;
        perform p11_notify_near_turn(NEW.day, NEW.period::text);
      end if;
      if NEW.called_at is not null and NEW.called_at is distinct from OLD.called_at and NEW.customer_id is not null then
        insert into customer_notifications(customer_id, appointment_id, kind, title, body)
        values (NEW.customer_id, NEW.id, 'called', 'دورك دلوقتي', 'اتنادى عليك — اتفضل على الصالون')
        on conflict (appointment_id, kind) do nothing;
      end if;
    end if;
  exception when others then
    raise warning 'p11 notify/learn: %', sqlerrm;
  end;
  return NEW;
end $$;

create or replace function public.p31_carry_over(p_day date) returns integer
language plpgsql security definer set search_path to 'public' as $$
declare r record; v_n int := 0; v_tn int; v_qn int; v_code text;
begin
  if p_day is null then return 0; end if;
  perform set_config('p31.carry', '1', true);
  for r in
    select a.id, a.barber_id, a.day, a.customer_id, a.period::text per, a.ticket_code, a.carried_from,
           row_number() over (partition by a.barber_id order by a.sort_at, a.id) rn,
           count(*) over (partition by a.barber_id) cnt,
           (select min(x.sort_at) from appointments x where x.barber_id is not distinct from a.barber_id and x.day = p_day) vmin
      from appointments a
     where a.day < p_day and a.day >= p_day - 3
       and a.status::text in ('upcoming', 'checked_in')
     order by a.barber_id, a.sort_at, a.id
  loop
    select coalesce(max(x.ticket_no), 0) + 1 into v_tn from appointments x
     where x.barber_id is not distinct from r.barber_id and x.day = p_day and x.period = r.per;
    select coalesce(max(x.queue_no), 0) + 1 into v_qn from appointments x
     where x.barber_id is not distinct from r.barber_id and x.day = p_day;
    v_code := case when r.barber_id is null then r.ticket_code else barber_letter(r.barber_id) || '-' || lpad(v_qn::text, 3, '0') end;
    update appointments set
        day = p_day, status = 'upcoming', ticket_no = v_tn, queue_no = v_qn, ticket_code = v_code,
        orig_ticket_code = coalesce(orig_ticket_code, r.ticket_code),
        carried_from = coalesce(r.carried_from, r.day),
        sort_at = coalesce(r.vmin, now()) - ((r.cnt - r.rn + 1) * interval '1 second'),
        starts_at = (p_day + (select pr.s from period_range(r.per) pr)) at time zone my_tz(),
        called_at = null, eta = null, on_way_at = null, arrived_at = null, present_at = null
     where id = r.id;
    if r.customer_id is not null then
      insert into customer_notifications(customer_id, appointment_id, kind, title, body)
      values (r.customer_id, r.id, 'carried_over', 'اتنقل حجزك لليوم',
              'مقدرناش نلحقك اليوم اللي فات، فاتنقل حجزك لليوم وهتكون من أول الناس أول ما الحلاق يوصل.')
      on conflict (appointment_id, kind) do nothing;
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke all on function public.p31_carry_over(date) from public, anon, authenticated;

-- لما الحلاق يسجّل حضور: نبّه أصحاب الحجوزات المرحّلة عنده
create or replace function public.p31_attendance_checkin() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  begin
    if NEW.check_out is null then
      insert into customer_notifications(customer_id, appointment_id, kind, title, body)
      select a.customer_id, a.id, 'carried_barber_in', 'الحلاق وصل', 'الحلاق وصل الصالون ودورك من أول الناس — تعالى دلوقتي.'
        from appointments a
       where a.barber_id = NEW.staff_id and a.day = biz_today() and a.carried_from is not null
         and a.status::text = 'upcoming' and a.customer_id is not null
      on conflict (appointment_id, kind) do nothing;
    end if;
  exception when others then raise warning 'p31 checkin notify: %', sqlerrm;
  end;
  return NEW;
end $$;
drop trigger if exists zz_p31_attendance_checkin on public.attendance;
create trigger zz_p31_attendance_checkin after insert on public.attendance
  for each row execute function public.p31_attendance_checkin();

-- فتح اليوم يرحّل الحجوزات (نفس الدالة الحالية + سطر الترحيل قبل الـ return)
create or replace function public.open_business_day(p_day date default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare cal date := (now() at time zone my_tz())::date; v date := coalesce(p_day, (now() at time zone my_tz())::date); o date; lastc timestamptz; lastd date;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select day into o from business_days where closed_at is null;
  if o is not null then raise exception 'فيه يوم مفتوح بالفعل (%). اقفله الأول من الخزنة.', o; end if;
  if v > cal then raise exception 'مينفعش تفتح يوم لسه ما جاش'; end if;
  if exists (select 1 from cash_closings c where c.day >= v) then raise exception 'يوم % أو اللي بعده اتقفل قبل كده (اتعمله جرد). اختار يوم بعد آخر يوم اتقفل، أو امسح الجرد من الخزنة الأول.', v; end if;
  select max(day), max(closed_at) into lastd, lastc from business_days;
  if p_day is not null and lastd is not null and v <= lastd then raise exception 'اليوم ده (%) اتفتح قبل كده. اختار يوم بعد %.', v, lastd; end if;
  if p_day is not null and lastc is not null and (((now() at time zone my_tz()) + least(0, v - biz_natural_day()) * interval '1 day') at time zone my_tz()) < lastc then
    raise exception 'آخر يوم اتقفل % — لازم تختار يوم بعده.', to_char(lastc at time zone my_tz(), 'YYYY-MM-DD HH24:MI'); end if;
  /* p26_guard */
  if p_day is null and exists (select 1 from invoices i where (i.created_at at time zone my_tz())::date = v - 1)
     and not exists (select 1 from cash_closings c where c.day = v - 1)
     and not exists (select 1 from business_days b where b.day = v - 1 and b.closed_at is not null) then
    raise exception 'يوم % فيه شغل ولسه ما اتقفلش بجرد الدرج. اقفله الأول من الخزنة (اختار يوم % واعمل قفل اليوم) وبعدها افتح اليوم الجديد.', v - 1, v - 1;
  end if;
  insert into business_days(day, opened_at, opened_by)
    values (v, case when v < ((now() at time zone my_tz()) - interval '6 hours')::date then (v::timestamp at time zone my_tz()) else now() end, auth.uid())
    on conflict (day) do update set closed_at = null, closed_by = null, opened_by = auth.uid();
  /* p31_carry */
  begin perform p31_carry_over(v); exception when others then raise warning 'p31 carry: %', sqlerrm; end;
  return business_day_state();
end $$;
