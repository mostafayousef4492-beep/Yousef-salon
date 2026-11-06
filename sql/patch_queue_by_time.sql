-- ترتيب الدور بوقت الحجز (الأول يحجز الأول يتخدم) بدل الفترة.
-- قبل كده شاشة الصنايعي والكاشير كانت بتترتّب بـ sort_at (وقت الحجز) عبر كل الفترات، لكن
-- اللي العميل كان بيشوفه (قدامك كام / الوقت المتوقّع / "أنت التالي") كان بيعدّ نفس الفترة بس —
-- فزبون حجز 4:58 العصر كان بيشوف "قدامك 2" وهو فعلاً بعد 8. الباتش ده بيشيل شرط الفترة من الحساب كله.
-- الفترة فاضلة بتحدد الحلاقين المتاحين وسقف الحجز للفترة (max_queue_per_period) بس.
-- للتراجع: شغّل نسخ الدوال القديمة (من الباك أب/الريبو) — مفيش بيانات بتتغيّر.

create or replace function public.p11_ahead(p_id bigint) returns integer
language sql stable security definer set search_path to 'public' as $$
  select count(*)::int
  from appointments m
  join appointments a
    on a.id <> m.id and a.day = m.day
   and (a.sort_at, a.id) < (m.sort_at, m.id)
   and a.status::text in ('upcoming','checked_in','in_service')
   and (m.barber_id is null or a.barber_id is null or a.barber_id = m.barber_id)
  where m.id = p_id
$$;

create or replace function public.p11_queue_core(p_id bigint) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare m appointments%rowtype; v_ahead int; v_wait numeric := 0; v_est numeric; r record;
        v_nb int; v_cur int; v_bname text; v_th numeric;
begin
  select * into m from appointments where id = p_id;
  if not found then return null; end if;
  v_ahead := p11_ahead(p_id);
  v_th    := p11_cfg_num('near_turn_threshold', 2);

  for r in
    select a.id, a.status::text st, a.service_started_at ss
      from appointments a
     where a.id <> m.id and a.day = m.day
       and (a.sort_at, a.id) < (m.sort_at, m.id)
       and a.status::text in ('upcoming','checked_in','in_service')
       and (m.barber_id is null or a.barber_id is null or a.barber_id = m.barber_id)
  loop
    v_est := p11_est_minutes(r.id);
    if r.st = 'in_service' and r.ss is not null then
      v_est := greatest(v_est - extract(epoch from (now() - r.ss)) / 60.0, 1);
    end if;
    v_wait := v_wait + v_est;
  end loop;

  if m.barber_id is null then            -- حلاق مفتوح: وزّع الانتظار على الحلاقين الموجودين
    select greatest(count(*), 1) into v_nb
      from attendance t join profiles pr on pr.id = t.staff_id
     where pr.role::text = 'barber' and t.check_out is null
       and (t.check_in at time zone p11_tz())::date = m.day;
    v_wait := v_wait / v_nb;
  end if;

  select min(a.ticket_no) into v_cur from appointments a
   where a.day = m.day and a.status::text = 'in_service'
     and (m.barber_id is null or a.barber_id is null or a.barber_id = m.barber_id);
  select full_name into v_bname from profiles where id = m.barber_id;

  return jsonb_build_object(
    'id', m.id, 'status', m.status::text, 'day', m.day, 'period', m.period::text,
    'ticket_no', m.ticket_no, 'ticket_code', m.ticket_code, 'barber_id', m.barber_id, 'barber_name', v_bname,
    'ahead', v_ahead, 'est_wait_min', round(v_wait), 'est_service_min', round(p11_est_minutes(m.id)),
    'current_no', v_cur, 'called', m.called_at is not null,
    'near_turn', (m.status::text = 'upcoming' and v_ahead <= v_th and v_th >= 0),
    'near_turn_threshold', v_th);
end $$;

create or replace function public.public_ticket(p_id bigint, p_phone text)
returns table(id bigint, day date, period text, ticket_no integer, status appt_status, called boolean, eta text, finished boolean, barber_name text, current_no integer, ahead bigint, est_min bigint, total numeric, services text)
language sql stable security definer set search_path to 'public' as $$
  select a.id, a.day, a.period, a.ticket_no, a.status, a.called_at is not null, a.eta, a.finished_at is not null, pr.full_name,
    (select x.ticket_no from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.status = 'in_service' order by x.sort_at limit 1),
    (select count(*) from appointments x where x.barber_id = a.barber_id and x.day = a.day and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments x join appointment_services s2 on s2.appointment_id = x.id join services sv on sv.id = s2.service_id
      where x.barber_id = a.barber_id and x.day = a.day and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')), 0),
    coalesce((select sum(sv.price) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), 0),
    coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), '')
  from appointments a left join profiles pr on pr.id = a.barber_id
  where a.id = p_id and a.customer_id in (select c.id from customers c where c.phone = regexp_replace(coalesce(p_phone,''), '\D', '', 'g')) $$;

create or replace function public.queue_status(p_id bigint)
returns table(id bigint, day date, period text, ticket_no integer, ticket_code text, status appt_status, called boolean, eta text, finished boolean, barber_name text, current_no integer, ahead bigint, est_min bigint, total numeric, services text)
language sql stable security definer set search_path to 'public' as $$
  select a.id, a.day, a.period, a.ticket_no, a.ticket_code, a.status, a.called_at is not null, a.eta, a.finished_at is not null, pr.full_name,
    (select x.ticket_no from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.status = 'in_service' order by x.sort_at limit 1),
    (select count(*) from appointments x where x.barber_id = a.barber_id and x.day = a.day and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments x join appointment_services s2 on s2.appointment_id = x.id join services sv on sv.id = s2.service_id
      where x.barber_id = a.barber_id and x.day = a.day and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')), 0),
    coalesce((select sum(sv.price) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), 0),
    coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), '')
  from appointments a left join profiles pr on pr.id = a.barber_id
  where a.id = p_id and a.customer_id in (select c.id from customers c where c.user_id = auth.uid()) $$;

-- عدّاد الحجز: كل اللي عند الحلاق في اليوم (مش الفترة بس)
create or replace function public.available_barbers(p_day date, p_period text)
returns table(id uuid, full_name text, waiting bigint, est_min bigint)
language sql stable security definer set search_path to 'public' as $$
  select b.barber_id, p.full_name,
    (select count(*) from appointments a where a.barber_id = b.barber_id and a.day = p_day and a.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments a join appointment_services x on x.appointment_id = a.id join services sv on sv.id = x.service_id
      where a.barber_id = b.barber_id and a.day = p_day and a.status in ('upcoming','checked_in','in_service')), 0)
  from barber_hours(p_day) b join profiles p on p.id = b.barber_id
       left join barber_spill(p_day) sp on sp.barber_id = b.barber_id, period_range(p_period) r
  where p19_present(b.barber_id, p_day) and ((not b.is_off and b.start_time < r.e and b.end_time > r.s)
     or (sp.spill_end is not null and sp.spill_end > r.s and '00:00'::time < r.e))
  order by 4 $$;

create or replace function public.skip_move(p_id bigint, p_mode text) returns void
language plpgsql security definer set search_path to 'public' as $$
declare a appointments; n appointments; v_old timestamptz;
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  if p_mode not in ('one', 'end') then raise exception 'اختار تخطّي زبون واحد أو لآخر الدور'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تتخطّى التذكرة دي'; end if;

  if p_mode = 'end' then
    if not exists (select 1 from appointments x
                    where x.id <> a.id and x.barber_id is not distinct from a.barber_id and x.day = a.day
                      and x.status::text in ('upcoming', 'checked_in') and (x.sort_at, x.id) > (a.sort_at, a.id)) then
      raise exception 'التذكرة دي أصلاً آخر واحد في الدور';
    end if;
    update appointments set sort_at = clock_timestamp(), called_at = null where id = a.id;
  else
    select * into n from appointments x
     where x.id <> a.id and x.barber_id is not distinct from a.barber_id and x.day = a.day
       and x.status::text in ('upcoming', 'checked_in') and (x.sort_at, x.id) > (a.sort_at, a.id)
     order by x.sort_at, x.id limit 1 for update;
    if not found then raise exception 'مفيش حد بعده في الدور'; end if;
    v_old := a.sort_at;
    update appointments set sort_at = n.sort_at, called_at = null where id = a.id;
    update appointments set sort_at = v_old where id = n.id;
  end if;
end $$;

create or replace function public.p17_urgent_place(p_id bigint) returns void
language plpgsql security definer set search_path to 'public' as $$
declare a appointments; v_first timestamptz; v_lastu timestamptz; v_new timestamptz;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  perform set_config('p17.urgent', '1', true);
  select min(x.sort_at) filter (where not x.is_urgent), max(x.sort_at) filter (where x.is_urgent)
    into v_first, v_lastu
    from appointments x
   where x.barber_id is not distinct from a.barber_id and x.day = a.day
     and x.id <> a.id and x.status::text in ('upcoming', 'checked_in');
  v_new := case when v_lastu is not null then v_lastu + interval '1 millisecond'
                when v_first is not null then v_first - interval '1 second'
                else a.sort_at end;
  update appointments set is_urgent = true, urgent_state = 'approved', urgent_by = auth.uid(), urgent_at = coalesce(urgent_at, now()), sort_at = least(v_new, a.sort_at)
   where id = p_id;
  perform p15_log(p_id, 'urgent_approved', null, '{}'::jsonb);
end $$;

-- إشعارات الترتيب: كل زبائن الحلاق في اليوم (مش الفترة بس). p_period فاضل في التوقيع للتوافق.
create or replace function public.p14_notify_queue(p_barber uuid, p_day date, p_period text, p_except bigint default null)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_th numeric := p11_cfg_num('near_turn_threshold', 2);
begin
  if p_barber is null or p_day is null then return; end if;
  insert into customer_notifications(customer_id, appointment_id, kind, title, body)
  select a.customer_id, a.id, 'pos:' || x.n || ':' || (coalesce(h.cnt, 0) + 1), 'اتغيّر ترتيبك',
         case when x.n = 0 then 'أنت التالي' else 'ترتيبك دلوقتي: فاضل ' || x.n || ' قبلك' end
    from appointments a
    cross join lateral (select p11_ahead(a.id) as n) x
    left join lateral (select count(*) as cnt,
                              (array_agg(split_part(cn.kind, ':', 2) order by cn.id desc))[1] as last_n
                         from customer_notifications cn
                        where cn.appointment_id = a.id and cn.kind ~ '^(pos|booked|barber_changed):') h on true
   where a.barber_id = p_barber and a.day = p_day
     and a.status::text in ('upcoming','checked_in') and a.customer_id is not null
     and a.id is distinct from p_except
     and h.last_n is distinct from x.n::text
     and (x.n > v_th or exists (select 1 from customer_notifications nt
                                 where nt.appointment_id = a.id and nt.kind = 'near_turn' and nt.created_at < now()))
  on conflict do nothing;
end $$;

create or replace function public.p11_notify_near_turn(p_day date, p_period text) returns void
language plpgsql security definer set search_path to 'public' as $$
declare v_th numeric;
begin
  if p_day is null or not p11_cfg_bool('near_turn_notifications', true) then return; end if;
  v_th := p11_cfg_num('near_turn_threshold', 2);
  if v_th < 0 then return; end if;
  insert into customer_notifications(customer_id, appointment_id, kind, title, body)
  select a.customer_id, a.id, 'near_turn', 'اقترب دورك',
         case when x.n = 0 then 'أنت التالي — جهّز نفسك' else 'فاضل ' || x.n || ' قبلك — جهّز نفسك' end
  from appointments a
  cross join lateral (select p11_ahead(a.id) n) x
  where a.day = p_day
    and a.status::text = 'upcoming'
    and a.customer_id is not null
    and x.n <= v_th
  on conflict (appointment_id, kind) do nothing;
end $$;
