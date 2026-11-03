-- ============================================================================
-- patch_queue_v2.sql — الطابور والتذاكر (المرحلة 4-أ)
-- ============================================================================
-- إضافات فقط: مفيش جدول ولا عمود اتحذف ولا بيانات اتغيّرت (غير تعبئة sort_at).
-- شغّله في SQL Editor على نسخة تجريبية (branch) الأول. الملف بيتشغّل مرة واحدة أو أكتر (idempotent).
--
-- اللي بيعمله:
--   1) ترقيم يومي لكل حلاق بحرف:  A-001, A-002 ... M-001  (بيبدأ من 001 كل يوم، والتاريخ القديم محفوظ).
--   2) حالات واضحة محمية في قاعدة البيانات (مش في الواجهة بس):
--        انتظار → تم الاستدعاء → حاضر → جارٍ تنفيذ الخدمة → مكتملة   |   ملغاة / لم يحضر (تخطّي)
--   3) نداء يدوي مع عدّاد محاولات، الحلاق يؤكد الحضور، الكاشير يبدأ الخدمة، الحلاق يؤكد الانتهاء.
--   4) التذكرة بتخرج من الطابور أول ما الحلاق يؤكد الانتهاء، حتى لو الفاتورة لسه ما اتدفعتش.
--   5) تخطّي (بسبب مسجّل) وإرجاع للتذكرة لآخر الطابور بنفس رقمها.
--   6) طلب نقل لحلاق تاني بيحتاج موافقة (الحلاق أو المدير)، والرقم الأصلي بيتحفظ.
--   7) سجل تدقيق للتذاكر (ticket_events) للقراءة فقط: مين، إمتى، إيه اللي اتغيّر، والسبب.
--   8) العميل ما يقدرش يأكّد حضوره بنفسه (إشارة «وصلت» بس) — الحلاق هو اللي يأكّد.
--
-- للتراجع: انظر آخر الملف.
-- ============================================================================

-- ---------- 1) أعمدة جديدة ----------
alter table public.appointments
  add column if not exists queue_no        int,          -- رقم الطابور اليومي للحلاق (يبدأ من 1 كل يوم)
  add column if not exists ticket_code     text,         -- A-001
  add column if not exists sort_at         timestamptz,  -- ترتيب الانتظار الفعلي (الإرجاع/النقل بيحدّثه، الرقم ثابت)
  add column if not exists call_count      int not null default 0,
  add column if not exists present_at      timestamptz,
  add column if not exists skip_reason     text,
  add column if not exists skipped_by      uuid,
  add column if not exists orig_ticket_code text,
  add column if not exists orig_barber_id  uuid,
  add column if not exists transfer_count  int not null default 0;

update public.appointments set sort_at = coalesce(created_at, starts_at, now()) where sort_at is null;
alter table public.appointments alter column sort_at set default clock_timestamp();
alter table public.appointments alter column sort_at set not null;

alter table public.profiles add column if not exists queue_letter text;
do $$ begin
  alter table public.profiles add constraint profiles_queue_letter_chk check (queue_letter is null or queue_letter ~ '^[A-Z]$');
exception when duplicate_object then null; end $$;
create unique index if not exists uq_profiles_queue_letter on public.profiles(queue_letter) where queue_letter is not null;

create unique index if not exists uq_appt_barber_day_queue_no
  on public.appointments(barber_id, day, queue_no) where queue_no is not null;
create index if not exists ix_appt_barber_day_sort
  on public.appointments(barber_id, day, sort_at, id);

-- حلاق واحد بس يكون عنده تذكرة «جارٍ تنفيذ» في نفس الوقت (لو فيه بيانات قديمة مخالفة بيتخطّى الفهرس وبيطلّع تنبيه)
do $$ begin
  create unique index if not exists uq_appt_one_in_service_per_barber
    on public.appointments(barber_id) where status = 'in_service';
exception when others then
  raise notice 'تم تخطي فهرس حلاق-واحد-في-الخدمة: فيه تذاكر in_service مكرّرة لنفس الحلاق (%). صفّيها وشغّل الملف تاني.', sqlerrm;
end $$;

-- ---------- 2) حرف الحلاق ----------
create or replace function public.barber_letter(p_barber uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v text; l text;
begin
  select queue_letter into v from profiles where id = p_barber;
  if v is not null then return v; end if;
  perform pg_advisory_xact_lock(hashtextextended('p15letters', 0));
  select queue_letter into v from profiles where id = p_barber;
  if v is not null then return v; end if;
  select x into l from unnest(string_to_array('A B C D E F G H I J K L M N O P Q R S T U V W X Y Z', ' ')) x
   where not exists (select 1 from profiles p where p.queue_letter = x) order by x limit 1;
  if l is null then raise exception 'مفيش حروف متاحة لطوابير الحلاقين'; end if;
  update profiles set queue_letter = l where id = p_barber;
  return l;
end $$;
revoke all on function public.barber_letter(uuid) from public, anon, authenticated;

-- تعيين حروف للحلاقين الحاليين (بترتيب التسجيل)
do $$ declare r record;
begin
  for r in select id from profiles where role::text = 'barber' and queue_letter is null order by created_at, id loop
    perform public.barber_letter(r.id);
  end loop;
end $$;

-- ---------- 3) سجل التدقيق (للقراءة فقط) ----------
create table if not exists public.ticket_events (
  id             bigint generated always as identity primary key,
  appointment_id bigint,
  ticket_code    text,
  barber_id      uuid,
  day            date,
  event          text not null,
  from_status    text,
  to_status      text,
  actor          uuid,
  actor_role     text,
  reason         text,
  detail         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index if not exists ix_ticket_events_appt on public.ticket_events(appointment_id, created_at);
create index if not exists ix_ticket_events_day  on public.ticket_events(day, created_at);
alter table public.ticket_events enable row level security;
revoke all on public.ticket_events from anon, authenticated;
grant select on public.ticket_events to authenticated;
drop policy if exists ticket_events_read on public.ticket_events;
create policy ticket_events_read on public.ticket_events for select to authenticated
  using (is_mgr() or has_perm('manage_appts') or barber_id = auth.uid());

create or replace function public.p15_events_readonly() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'سجل التدقيق للقراءة فقط'; end $$;
drop trigger if exists zz_p15_events_ro on public.ticket_events;
create trigger zz_p15_events_ro before update or delete on public.ticket_events
  for each row execute function public.p15_events_readonly();

create or replace function public.p15_log(p_appt bigint, p_event text, p_reason text default null, p_detail jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  select * into a from appointments where id = p_appt;
  insert into ticket_events(appointment_id, ticket_code, barber_id, day, event, actor, actor_role, reason, detail)
  values (p_appt, coalesce(a.ticket_code, '#' || a.ticket_no), a.barber_id, a.day, p_event, auth.uid(), p11_role(), p_reason, coalesce(p_detail, '{}'::jsonb));
end $$;
revoke all on function public.p15_log(bigint, text, text, jsonb) from public, anon, authenticated;

-- ---------- 4) حارس الحالات (بيمنع أي انتقال غير قانوني حتى لو جه من تحديث مباشر) ----------
create or replace function public.p15_appt_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare o text := OLD.status::text; n text := NEW.status::text; ok boolean;
begin
  if n = o then return NEW; end if;
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
drop trigger if exists zz_p15_guard on public.appointments;
create trigger zz_p15_guard before update of status on public.appointments
  for each row execute function public.p15_appt_guard();

create or replace function public.p15_appt_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare ev text; rs text;
begin
  if NEW.status is not distinct from OLD.status then return NEW; end if;
  ev := case NEW.status::text
    when 'checked_in' then 'present'
    when 'in_service' then 'service_start'
    when 'done'       then 'service_done'
    when 'cancelled'  then 'cancel'
    when 'no_show'    then 'skip'
    when 'upcoming'   then 'return' end;
  rs := case when NEW.status::text = 'no_show' then NEW.skip_reason else nullif(current_setting('p15.reason', true), '') end;
  insert into ticket_events(appointment_id, ticket_code, barber_id, day, event, from_status, to_status, actor, actor_role, reason, detail)
  values (NEW.id, coalesce(NEW.ticket_code, '#' || NEW.ticket_no), NEW.barber_id, NEW.day, ev, OLD.status::text, NEW.status::text,
          auth.uid(), coalesce(p11_role(), case when auth.uid() is null then 'system' end), rs, '{}'::jsonb);
  return NEW;
end $$;
drop trigger if exists zz_p15_audit on public.appointments;
create trigger zz_p15_audit after update of status on public.appointments
  for each row execute function public.p15_appt_audit();

-- صلاحية التعامل مع تذكرة: المدير/الكاشير (manage_appts) أو الحلاق صاحب التذكرة
create or replace function public.p15_can_touch(p_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(is_mgr() or has_perm('manage_appts')
    or (has_perm('view_own_schedule') and exists (select 1 from appointments a where a.id = p_id and a.barber_id = auth.uid())), false)
$$;
revoke all on function public.p15_can_touch(bigint) from public, anon;
grant execute on function public.p15_can_touch(bigint) to authenticated;

-- ---------- 5) أوامر الطابور ----------
-- نداء (وإعادة نداء): بيسجّل كل محاولة ووقتها
create or replace function public.call_ticket(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تنادي على التذكرة دي'; end if;
  update appointments set called_at = now(), call_count = call_count + 1 where id = p_id;
  perform p15_log(p_id, case when a.call_count = 0 then 'call' else 'recall' end, null, jsonb_build_object('attempt', a.call_count + 1));
end $$;

-- الحلاق يؤكد إن العميل حضر (بعد النداء). المدير/الكاشير يقدروا يأكدوا حضور عميل واقف قدامهم.
create or replace function public.confirm_arrival(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text <> 'upcoming' then raise exception 'التذكرة دي مش في الانتظار'; end if;
  if a.called_at is null and not (is_mgr() or has_perm('manage_appts')) then
    raise exception 'نادي على العميل الأول'; end if;
  update appointments set status = 'checked_in' where id = p_id;
end $$;

-- الكاشير يبدأ الخدمة رسميًا (مش الحلاق)
create or replace function public.start_service(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not (can_use_pos() or has_perm('manage_appts') or is_mgr()) then raise exception 'غير مصرح'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text <> 'checked_in' then raise exception 'العميل لازم يكون حاضر الأول'; end if;
  begin
    update appointments set status = 'in_service' where id = p_id;
  exception when unique_violation then
    raise exception 'الحلاق ده عنده خدمة شغّالة بالفعل';
  end;
end $$;

-- الحلاق يؤكد انتهاء الخدمة → التذكرة تخرج من الطابور فورًا (الفاتورة والدفع بعدين، منفصلين)
create or replace function public.finish_ticket(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text <> 'in_service' then raise exception 'الخدمة لسه ما بدأتش'; end if;
  update appointments set status = 'done', finished_at = now() where id = p_id;
end $$;

-- تخطّي عميل (لم يحضر) — السبب إجباري ومتسجّل
create or replace function public.skip_ticket(p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments; r text := btrim(coalesce(p_reason, ''));
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  if char_length(r) < 2 then raise exception 'اكتب سبب التخطّي'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تتخطّى التذكرة دي'; end if;
  update appointments set status = 'no_show', skip_reason = r, skipped_by = auth.uid() where id = p_id;
end $$;

create or replace function public.mark_no_show(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin perform skip_ticket(p_id, 'لم يحضر'); end $$;

-- إرجاع تذكرة متخطّاة لآخر الطابور بنفس رقمها
create or replace function public.return_ticket(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare a appointments; v_today date := (now() at time zone my_tz())::date;
begin
  if not p15_can_touch(p_id) then raise exception 'غير مصرح'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  if a.status::text <> 'no_show' then raise exception 'التذكرة دي مش متخطّاة'; end if;
  if a.day <> v_today then raise exception 'مينفعش ترجّع تذكرة من يوم تاني'; end if;
  perform set_config('p15.return', '1', true);
  begin
    update appointments set status = 'upcoming', sort_at = clock_timestamp(), called_at = null, no_show_at = null,
           skip_reason = null, skipped_by = null where id = p_id;
  exception when unique_violation then
    perform set_config('p15.return', '', true);
    raise exception 'العميل ده عنده تذكرة نشطة تانية';
  end;
  perform set_config('p15.return', '', true);
end $$;

create or replace function public.set_my_appt_status(p_id bigint, p_status appt_status) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_perm('view_own_schedule') then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from appointments where id = p_id and barber_id = auth.uid()) then raise exception 'مش تذكرتك'; end if;
  if p_status = 'checked_in' then perform confirm_arrival(p_id);
  elsif p_status = 'in_service' then raise exception 'الكاشير هو اللي يبدأ الخدمة';
  else raise exception 'حالة غير مسموحة'; end if;
end $$;

-- الكاشير يخلّص الإجراء المالي: لو التذكرة لسه ما اكتملتش نكمّلها (بنفس مسار الحالات القانوني)
create or replace function public.p15_complete_ticket(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s text;
begin
  select status::text into s from appointments where id = p_id for update;
  if s is null or s in ('done', 'cancelled') then return; end if;
  if s = 'no_show' then raise exception 'التذكرة دي اتخطّت — رجّعها الأول'; end if;
  if s = 'upcoming' then update appointments set status = 'checked_in' where id = p_id; end if;
  update appointments set status = 'done', finished_at = coalesce(finished_at, now()) where id = p_id;
end $$;
revoke all on function public.p15_complete_ticket(bigint) from public, anon, authenticated;

-- تذاكر اكتملت خدمتها ولسه ما اتحاسبتش (الكاشير)
create or replace function public.tickets_awaiting_payment(p_day date default null)
returns table(id bigint, ticket_code text, ticket_no int, barber_id uuid, barber_name text, customer_id bigint, customer_name text, finished_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.id, coalesce(a.ticket_code, '#' || a.ticket_no), a.ticket_no, a.barber_id, p.full_name, a.customer_id, c.name, a.finished_at
    from appointments a left join profiles p on p.id = a.barber_id left join customers c on c.id = a.customer_id
   where (can_use_pos() or is_mgr()) and a.status = 'done'
     and a.day = coalesce(p_day, (now() at time zone my_tz())::date)
     and not exists (select 1 from invoices i where i.appointment_id = a.id)
   order by a.finished_at nulls last, a.id
$$;
revoke all on function public.tickets_awaiting_payment(date) from public, anon;
grant execute on function public.tickets_awaiting_payment(date) to authenticated;

-- ---------- 6) النقل بين الحلاقين ----------
create table if not exists public.ticket_transfers (
  id             bigint generated always as identity primary key,
  appointment_id bigint not null,
  from_barber    uuid,
  to_barber      uuid not null,
  requested_by   uuid,
  reason         text,
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by     uuid,
  decided_at     timestamptz,
  decision_note  text,
  old_code       text,
  new_code       text,
  created_at     timestamptz not null default now()
);
create unique index if not exists uq_transfer_one_pending on public.ticket_transfers(appointment_id) where status = 'pending';
alter table public.ticket_transfers enable row level security;
revoke all on public.ticket_transfers from anon, authenticated;
grant select on public.ticket_transfers to authenticated;
drop policy if exists ticket_transfers_read on public.ticket_transfers;
create policy ticket_transfers_read on public.ticket_transfers for select to authenticated
  using (is_mgr() or has_perm('manage_appts') or from_barber = auth.uid() or to_barber = auth.uid() or requested_by = auth.uid());

-- النقل الفعلي: آخر الطابور عند الحلاق الجديد برقم جديد، والرقم الأصلي محفوظ ومربوط في السجل
create or replace function public.p15_move(p_id bigint, p_barber uuid, p_req bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  m appointments%rowtype; k1 text; k2 text; d1 text; d2 text; v_qn int; v_tn int; v_code text; v_old text; v_bn text; v_user uuid;
  v_cap int := coalesce((setting('max_queue_per_period','12'::jsonb) #>> '{}')::int, 12); v_cnt int;
begin
  if p_barber is null then raise exception 'اختار الحلاق'; end if;
  select * into m from appointments where id = p_id;
  if not found then raise exception 'الحجز غير موجود'; end if;
  if m.barber_id = p_barber then return jsonb_build_object('ok', true, 'changed', false); end if;

  k1 := 'p14q:' || coalesce(m.barber_id::text,'-') || ':' || m.day::text || ':' || m.period;
  k2 := 'p14q:' || p_barber::text || ':' || m.day::text || ':' || m.period;
  d1 := 'p15d:' || coalesce(m.barber_id::text,'-') || ':' || m.day::text;
  d2 := 'p15d:' || p_barber::text || ':' || m.day::text;
  if k1 < k2 then perform pg_advisory_xact_lock(hashtextextended(k1,0)); perform pg_advisory_xact_lock(hashtextextended(k2,0));
  else perform pg_advisory_xact_lock(hashtextextended(k2,0)); perform pg_advisory_xact_lock(hashtextextended(k1,0)); end if;
  if d1 < d2 then perform pg_advisory_xact_lock(hashtextextended(d1,0)); perform pg_advisory_xact_lock(hashtextextended(d2,0));
  else perform pg_advisory_xact_lock(hashtextextended(d2,0)); perform pg_advisory_xact_lock(hashtextextended(d1,0)); end if;

  select * into m from appointments where id = p_id for update;
  if m.status::text not in ('upcoming', 'checked_in') then
    raise exception 'مينفعش تغيّر الحلاق بعد بدء الخدمة أو بعد انتهاء الحجز'; end if;
  if m.barber_id = p_barber then return jsonb_build_object('ok', true, 'changed', false); end if;
  if not exists (select 1 from available_barbers(m.day, m.period) ab where ab.id = p_barber) then
    raise exception 'الحلاق مش متاح في الفترة دي'; end if;

  select count(*) filter (where a.status::text <> 'cancelled') into v_cnt
    from appointments a where a.barber_id = p_barber and a.day = m.day and a.period = m.period;
  if v_cnt >= v_cap then raise exception 'قائمة الحلاق ده مكتملة'; end if;
  select coalesce(max(a.ticket_no),0) + 1 into v_tn from appointments a where a.barber_id = p_barber and a.day = m.day and a.period = m.period;
  select coalesce(max(a.queue_no),0) + 1 into v_qn from appointments a where a.barber_id = p_barber and a.day = m.day;
  v_code := barber_letter(p_barber) || '-' || lpad(v_qn::text, 3, '0');
  v_old := coalesce(m.ticket_code, '#' || m.ticket_no);

  update appointments set barber_id = p_barber, ticket_no = v_tn, queue_no = v_qn, ticket_code = v_code, sort_at = clock_timestamp(),
         called_at = null, eta = null,
         orig_ticket_code = coalesce(orig_ticket_code, v_old), orig_barber_id = coalesce(orig_barber_id, m.barber_id),
         transfer_count = transfer_count + 1
   where id = p_id;
  perform p15_log(p_id, 'transfer', null, jsonb_build_object('from_barber', m.barber_id, 'to_barber', p_barber, 'old_code', v_old, 'new_code', v_code, 'request_id', p_req));

  select full_name into v_bn from profiles where id = p_barber;
  begin
    insert into customer_notifications(customer_id, appointment_id, kind, title, body)
    values (m.customer_id, m.id, 'barber_changed:' || (m.transfer_count + 1)::text, 'اتغيّر الحلاق',
            'دورك دلوقتي عند ' || coalesce(v_bn,'—') || ' — رقم ' || v_code)
    on conflict do nothing;
    select user_id into v_user from customers where id = m.customer_id;
    if v_user is not null then
      perform push_send(array[v_user], 'اتغيّر الحلاق', 'دورك دلوقتي عند ' || coalesce(v_bn,'—') || ' — رقم ' || v_code, 'queue', 'mv-' || m.id, false);
    end if;
  exception when others then raise warning 'p15 move notify: %', sqlerrm;
  end;
  return jsonb_build_object('ok', true, 'changed', true, 'barber', v_bn, 'no', v_tn, 'code', v_code, 'old_code', v_old);
end $$;
revoke all on function public.p15_move(bigint, uuid, bigint) from public, anon, authenticated;

-- المسار القديم بقى يعدّي على نفس المنطق (المدير/الكاشير ينقلوا مباشرة وبيتسجّل)
create or replace function public.p14_reassign_core(p_id bigint, p_barber uuid) returns jsonb
language sql security definer set search_path = public as $$ select public.p15_move(p_id, p_barber, null) $$;

-- النقل الذاتي بالتليفون من غير موافقة اتقفل: لازم طلب نقل بموافقة
create or replace function public.public_change_barber(p_id bigint, p_phone text, p_barber uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin raise exception 'نقل التذكرة لحلاق تاني بيحتاج موافقة: اطلب النقل من تطبيق العميل'; end $$;
revoke execute on function public.public_change_barber(bigint, text, uuid) from public, anon;

-- العميل يطلب النقل (بعد إصدار التذكرة)
create or replace function public.request_transfer(p_id bigint, p_to uuid, p_reason text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare a appointments; v_id bigint; v_staff uuid[];
begin
  select a2.* into a from appointments a2 join customers c on c.id = a2.customer_id where a2.id = p_id and c.user_id = auth.uid();
  if a.id is null then raise exception 'مش تذكرتك'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تطلب نقل في الحالة دي'; end if;
  if p_to is null or p_to = a.barber_id then raise exception 'اختار حلاق تاني'; end if;
  if not exists (select 1 from available_barbers(a.day, a.period) ab where ab.id = p_to) then
    raise exception 'الحلاق مش متاح في الفترة دي'; end if;
  begin
    insert into ticket_transfers(appointment_id, from_barber, to_barber, requested_by, reason, old_code)
    values (a.id, a.barber_id, p_to, auth.uid(), nullif(btrim(coalesce(p_reason, '')), ''), coalesce(a.ticket_code, '#' || a.ticket_no))
    returning id into v_id;
  exception when unique_violation then raise exception 'عندك طلب نقل معلّق بالفعل';
  end;
  perform p15_log(a.id, 'transfer_request', p_reason, jsonb_build_object('to_barber', p_to, 'request_id', v_id));
  begin
    perform push_send(array_remove(array[a.barber_id, p_to], null), 'طلب نقل تذكرة', 'عميل طلب النقل — راجع الطلبات', 'appts', 'tr-' || v_id, false);
  exception when others then null; end;
  return v_id;
end $$;

-- الحلاق (الحالي أو الجديد) أو المدير/الكاشير يوافق أو يرفض. الرفض: التذكرة تفضل مكانها.
create or replace function public.decide_transfer(p_req bigint, p_ok boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t ticket_transfers; r jsonb; v_code text;
begin
  select * into t from ticket_transfers where id = p_req for update;
  if not found then raise exception 'الطلب مش موجود'; end if;
  if not (is_mgr() or has_perm('manage_appts') or auth.uid() in (t.from_barber, t.to_barber)) then raise exception 'غير مصرح'; end if;
  if t.status <> 'pending' then raise exception 'الطلب ده اتقرر فيه قبل كده'; end if;
  if p_ok then
    begin
      r := p15_move(t.appointment_id, t.to_barber, t.id);
    exception when others then
      update ticket_transfers set status = 'rejected', decided_by = auth.uid(), decided_at = now(),
             decision_note = 'تعذّر التنفيذ: ' || sqlerrm where id = p_req;
      perform p15_log(t.appointment_id, 'transfer_failed', sqlerrm, jsonb_build_object('request_id', p_req));
      raise;
    end;
    v_code := r->>'code';
    update ticket_transfers set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = p_note, new_code = v_code where id = p_req;
  else
    update ticket_transfers set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = p_note where id = p_req;
    perform p15_log(t.appointment_id, 'transfer_rejected', p_note, jsonb_build_object('request_id', p_req));
  end if;
  return jsonb_build_object('ok', true, 'approved', p_ok, 'code', v_code);
end $$;

create or replace function public.cancel_transfer_request(p_req bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update ticket_transfers t set status = 'cancelled', decided_at = now()
   where t.id = p_req and t.status = 'pending' and t.requested_by = auth.uid();
  if not found then raise exception 'مينفعش تلغي الطلب ده'; end if;
end $$;

revoke all on function public.call_ticket(bigint), public.confirm_arrival(bigint), public.start_service(bigint),
  public.finish_ticket(bigint), public.skip_ticket(bigint, text), public.mark_no_show(bigint), public.return_ticket(bigint),
  public.set_my_appt_status(bigint, appt_status), public.request_transfer(bigint, uuid, text),
  public.decide_transfer(bigint, boolean, text), public.cancel_transfer_request(bigint) from public, anon;
grant execute on function public.call_ticket(bigint), public.confirm_arrival(bigint), public.start_service(bigint),
  public.finish_ticket(bigint), public.skip_ticket(bigint, text), public.mark_no_show(bigint), public.return_ticket(bigint),
  public.set_my_appt_status(bigint, appt_status), public.request_transfer(bigint, uuid, text),
  public.decide_transfer(bigint, boolean, text), public.cancel_transfer_request(bigint) to authenticated;

-- ---------- 7) إصدار التذاكر: ترقيم يومي بحرف (منطق واحد لكل المسارات: موبايل، استقبال، كشك) ----------

CREATE OR REPLACE FUNCTION public.p14_make_ticket(p_c bigint, p_b uuid, p_day date, p_period text, p_services bigint[], p_status appt_status, p_source text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_b uuid := p_b; v_no int; v_id bigint; v_tz text := my_tz();
  v_max int := coalesce((setting('max_queue_per_period','12'::jsonb) #>> '{}')::int, 12);
  v_cnt int; v_ex record; v_cn text; v_qn int; v_code text;
  v_n int := coalesce(array_length(p_services,1), 0);
begin
  perform pg_advisory_xact_lock(hashtextextended('p14c:' || p_c::text, 0));

  select a.id, a.ticket_no, a.status::text as st into v_ex
    from appointments a
   where a.customer_id = p_c and a.status in ('upcoming','checked_in','in_service')
   order by a.id limit 1;
  if v_ex.id is not null then
    return jsonb_build_object('existing', true, 'id', v_ex.id, 'no', v_ex.ticket_no, 'status', v_ex.st);
  end if;

  if v_n > 10 then raise exception 'عدد الخدمات كبير'; end if;
  if v_n > 0 and (select count(*) from services s where s.id = any(p_services) and s.active)
               <> (select count(distinct x) from unnest(p_services) x) then
    raise exception 'في خدمة مش متاحة، حدّث الصفحة وجرّب تاني';
  end if;

  if v_b is null then
    -- اقتراح "أي حلاق": الأقل انتظارًا ثم الأقل مدة، والكاشير يقدر يغيّره بعدين
    select ab.id into v_b from available_barbers(p_day, p_period) ab
     order by ab.waiting, ab.est_min, ab.id limit 1;
  elsif not exists (select 1 from available_barbers(p_day, p_period) ab where ab.id = v_b) then
    raise exception 'الحلاق مش متاح في الفترة دي';
  end if;
  if v_b is null then raise exception 'مفيش حلاق متاح في الفترة دي'; end if;

  perform pg_advisory_xact_lock(hashtextextended('p14q:' || v_b::text || ':' || p_day::text || ':' || p_period, 0));

  perform pg_advisory_xact_lock(hashtextextended('p15d:' || v_b::text || ':' || p_day::text, 0));
  v_code := barber_letter(v_b);

  for i in 1..5 loop
    select count(*) filter (where a.status::text <> 'cancelled'), coalesce(max(a.ticket_no),0) + 1
      into v_cnt, v_no
      from appointments a where a.barber_id = v_b and a.day = p_day and a.period = p_period;
    select coalesce(max(a.queue_no),0) + 1 into v_qn from appointments a where a.barber_id = v_b and a.day = p_day;
    if v_cnt >= v_max then raise exception 'الفترة دي اكتملت، اختار فترة تانية'; end if;
    begin
      insert into appointments(customer_id, barber_id, starts_at, status, day, period, ticket_no, queue_no, ticket_code, booking_source)
      values (p_c, v_b, (p_day + (select r.s from period_range(p_period) r)) at time zone v_tz,
              p_status, p_day, p_period, v_no, v_qn, v_code || '-' || lpad(v_qn::text, 3, '0'), p_source)
      returning id into v_id;
      exit;
    exception when unique_violation then
      get stacked diagnostics v_cn = constraint_name;
      if v_cn = 'one_active_appt_per_customer' then
        select a.id, a.ticket_no, a.status::text as st into v_ex
          from appointments a
         where a.customer_id = p_c and a.status in ('upcoming','checked_in','in_service')
         order by a.id limit 1;
        return jsonb_build_object('existing', true, 'id', v_ex.id, 'no', v_ex.ticket_no, 'status', v_ex.st);
      end if;
      if i = 5 then raise exception 'الدور زحمة دلوقتي، جرّب تاني'; end if;
    end;
  end loop;

  insert into appointment_services(appointment_id, service_id)
    select v_id, s.id from services s where s.id = any(p_services) and s.active;
  return jsonb_build_object('existing', false, 'id', v_id, 'no', v_no, 'code', v_code || '-' || lpad(v_qn::text, 3, '0'), 'status', p_status::text);
end $function$;

CREATE OR REPLACE FUNCTION public.p11_ahead(p_id bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int
  from appointments m
  join appointments a
    on a.id <> m.id and a.day = m.day
   and a.period::text is not distinct from m.period::text
   and (a.sort_at, a.id) < (m.sort_at, m.id)
   and a.status::text in ('upcoming','checked_in','in_service')
   and (m.barber_id is null or a.barber_id is null or a.barber_id = m.barber_id)
  where m.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public.p11_queue_core(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       and a.period::text is not distinct from m.period::text
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
   where a.day = m.day and a.period::text is not distinct from m.period::text
     and a.status::text = 'in_service';
  select full_name into v_bname from profiles where id = m.barber_id;

  return jsonb_build_object(
    'id', m.id, 'status', m.status::text, 'day', m.day, 'period', m.period::text,
    'ticket_no', m.ticket_no, 'barber_id', m.barber_id, 'barber_name', v_bname,
    'ahead', v_ahead, 'est_wait_min', round(v_wait), 'est_service_min', round(p11_est_minutes(m.id)),
    'current_no', v_cur, 'called', m.called_at is not null,
    'near_turn', (m.status::text = 'upcoming' and v_ahead <= v_th and v_th >= 0),
    'near_turn_threshold', v_th);
end $function$;

CREATE OR REPLACE FUNCTION public.queue_status(p_id bigint)
 RETURNS TABLE(id bigint, day date, period text, ticket_no integer, status appt_status, called boolean, eta text, finished boolean, barber_name text, current_no integer, ahead bigint, est_min bigint, total numeric, services text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.id, a.day, a.period, a.ticket_no, a.status, a.called_at is not null, a.eta, a.finished_at is not null, pr.full_name,
    (select x.ticket_no from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.status = 'in_service' order by x.ticket_no limit 1),
    (select count(*) from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments x join appointment_services s2 on s2.appointment_id = x.id join services sv on sv.id = s2.service_id
      where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')), 0),
    coalesce((select sum(sv.price) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), 0),
    coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), '')
  from appointments a left join profiles pr on pr.id = a.barber_id
  where a.id = p_id and a.customer_id in (select c.id from customers c where c.user_id = auth.uid()) $function$;

CREATE OR REPLACE FUNCTION public.public_ticket(p_id bigint, p_phone text)
 RETURNS TABLE(id bigint, day date, period text, ticket_no integer, status appt_status, called boolean, eta text, finished boolean, barber_name text, current_no integer, ahead bigint, est_min bigint, total numeric, services text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.id, a.day, a.period, a.ticket_no, a.status, a.called_at is not null, a.eta, a.finished_at is not null, pr.full_name,
    (select x.ticket_no from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.status = 'in_service' order by x.ticket_no limit 1),
    (select count(*) from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments x join appointment_services s2 on s2.appointment_id = x.id join services sv on sv.id = s2.service_id
      where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and (x.sort_at, x.id) < (a.sort_at, a.id) and x.status in ('upcoming','checked_in','in_service')), 0),
    coalesce((select sum(sv.price) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), 0),
    coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), '')
  from appointments a left join profiles pr on pr.id = a.barber_id
  where a.id = p_id and a.customer_id in (select c.id from customers c where c.phone = regexp_replace(coalesce(p_phone,''), '\D', '', 'g')) $function$;

CREATE OR REPLACE FUNCTION public.ticket_eta(p_id bigint, p_state text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_state not in ('on_way','arrived') then raise exception 'حالة غير صحيحة'; end if;
  update appointments a set eta = p_state, status = a.status
   where a.id = p_id and a.called_at is not null and a.status in ('upcoming','checked_in')
     and a.customer_id in (select c.id from customers c where c.user_id = auth.uid());
  if not found then raise exception 'لسه ما اتنادش عليك'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.public_eta(p_id bigint, p_phone text, p_state text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_state not in ('on_way','arrived') then raise exception 'حالة غير صحيحة'; end if;
  update appointments a set eta = p_state, status = a.status
   where a.id = p_id and a.called_at is not null and a.status in ('upcoming','checked_in')
     and a.customer_id in (select c.id from customers c where c.phone = regexp_replace(coalesce(p_phone,''), '\D', '', 'g'));
  if not found then raise exception 'لسه ما اتنادش عليك'; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.pos_checkout(p_customer bigint, p_barber uuid, p_items jsonb, p_discount_pct numeric, p_discount_fixed numeric, p_method text, p_appointment bigint DEFAULT NULL::bigint, p_redemption bigint DEFAULT NULL::bigint, p_request bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; v_inv bigint; v_sub numeric := 0; v_disc numeric; v_total numeric; v_name text; v_price numeric; v_qty int;
        v_rd loyalty_redemptions; v_rw loyalty_rewards; v_rdisc numeric := 0; v_c customers; v_mult numeric; v_pts int; v_every int; v_ass uuid; v_apct numeric;
        v_pct numeric := coalesce(p_discount_pct,0); v_fx numeric := coalesce(p_discount_fixed,0); v_eff numeric; r discount_requests; v_loy boolean := p11_cfg_bool('ff_loyalty',true); v_base numeric;
begin
  if not can_use_pos() then raise exception 'غير مصرح'; end if;
  if v_pct < 0 or v_pct > 100 or v_fx < 0 then raise exception 'قيمة خصم غير صحيحة'; end if;
  if v_pct > 0 and v_fx > 0 then raise exception 'اختار خصم نسبة أو مبلغ، مش الاتنين'; end if;
  if p_method not in ('cash','card','wallet') then raise exception 'طريقة دفع غير مدعومة'; end if;
  if p_method = 'card' and not p11_cfg_bool('pay_card_enabled',true) then raise exception 'الدفع بالكارت متوقف'; end if;
  if p_method = 'wallet' and not p11_cfg_bool('pay_wallet_enabled',true) then raise exception 'الدفع بالمحفظة متوقف'; end if;
  if p_redemption is not null and not v_loy then raise exception 'برنامج الولاء متوقف'; end if;
  if p_appointment is not null then
    if p_customer is null then select a.customer_id into p_customer from appointments a where a.id = p_appointment; end if;
    if p_barber is null then select a.barber_id into p_barber from appointments a where a.id = p_appointment; end if;
  end if;
  insert into invoices(customer_id,barber_id,appointment_id,subtotal,discount,total,payment_method) values (p_customer,p_barber,p_appointment,0,0,0,p_method) returning id into v_inv;
  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := coalesce((it->>'qty')::int,1); v_ass := null; v_apct := null;
    if v_qty < 1 then raise exception 'كمية غير صحيحة'; end if;
    if it->>'type' = 'service' then select name, price into v_name, v_price from services where id = (it->>'id')::bigint;
      if nullif(it->>'assistant','') is not null then
        if p_barber is null then raise exception 'اختار الحلاق الأول قبل ما تحدد مساعد'; end if;
        select pr.id, pr.commission_pct into v_ass, v_apct from profiles pr where pr.id = (it->>'assistant')::uuid and pr.role = 'assistant';
        if v_ass is null then raise exception 'المساعد غير صالح'; end if;
      end if;
    else
      update products set stock = stock - v_qty where id = (it->>'id')::bigint returning name, price into v_name, v_price;
      insert into stock_movements(product_id,qty,reason) values ((it->>'id')::bigint,-v_qty,'sale');
    end if;
    if v_name is null then raise exception 'عنصر غير موجود في الفاتورة'; end if;
    insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price,assistant_id,assistant_pct) values (v_inv,it->>'type',(it->>'id')::bigint,v_name,v_qty,v_price,v_ass,v_apct);
    v_sub := v_sub + v_price * v_qty;
  end loop;

  -- قواعد الخصم (بعد معرفة الإجمالي)
  v_eff := case when v_sub > 0 then (v_sub * v_pct / 100 + v_fx) / v_sub * 100 else 0 end;
  if v_eff > 100 then raise exception 'الخصم أكبر من الفاتورة'; end if;
  if v_eff > p11_cfg_num('disc_global_max_pct',20) + 0.005 then raise exception 'الخصم فوق الحد الأقصى في النظام (% بالمية)', p11_cfg_num('disc_global_max_pct',20); end if;
  if v_eff > my_disc_limit() + 0.005 then
    select * into r from discount_requests where id = p_request for update;
    if not found or r.status <> 'approved' or r.requested_by <> auth.uid() or r.pct + 0.01 < v_eff or r.created_at < now() - interval '3 hours' then
      raise exception 'الخصم ده محتاج موافقة المدير';
    end if;
    update discount_requests set status = 'used' where id = r.id;
  end if;
  if v_eff > 0 and p_redemption is not null and not p11_cfg_bool('disc_stack_coupon',true) then raise exception 'مينفعش خصم مع كوبون ولاء'; end if;

  v_disc := v_sub * v_pct / 100 + v_fx;
  if p_redemption is not null then
    select * into v_rd from loyalty_redemptions where id = p_redemption and status = 'active' and customer_id = p_customer;
    if v_rd.id is null then raise exception 'الكوبون غير صالح'; end if;
    select * into v_rw from loyalty_rewards where id = v_rd.reward_id;
    v_rdisc := case v_rw.kind when 'amount' then v_rw.value when 'pct' then v_sub * v_rw.value / 100
      else coalesce((select ii.unit_price from invoice_items ii where ii.invoice_id = v_inv and ii.item_type = 'service' and ii.item_id = v_rw.service_id limit 1), 0) end;
    if v_rdisc <= 0 then raise exception 'الكوبون ده مش مناسب للفاتورة دي'; end if;
    update loyalty_redemptions set status = 'used', used_at = now(), invoice_id = v_inv where id = p_redemption;
  end if;
  v_disc := least(v_sub, v_disc + v_rdisc); v_total := v_sub - v_disc;
  update invoices set subtotal = v_sub, discount = v_disc, total = v_total where id = v_inv;
  update invoice_items set assistant_cut = round(unit_price * qty * (case when v_sub > 0 then (case when p11_cfg_bool('disc_affects_commission',true) then (v_sub - v_disc) / v_sub else 1 end) else 0 end) * assistant_pct / 100, 2)
   where invoice_id = v_inv and assistant_id is not null;

  if p_customer is not null then
    select * into v_c from customers where id = p_customer;
    if v_loy then
      select t.mult into v_mult from loyalty_tier(v_c.lifetime_points) t;
      v_base := case when p11_cfg_bool('disc_affects_points',true) then v_total else greatest(v_sub - v_rdisc, 0) end;
      v_pts := floor(v_base / greatest((setting('points_per_currency','10'::jsonb))::text::numeric, 1) * v_mult)::int;
      if v_pts > 0 then perform add_points(p_customer, v_pts, 'purchase', v_inv, 'فاتورة'); end if;
    end if;
    update customers set visits = visits + 1 where id = p_customer;
    if v_loy then
      v_every := greatest((setting('visit_bonus_every','5'::jsonb))::text::int, 1);
      if (v_c.visits + 1) % v_every = 0 then
        perform add_points(p_customer, (setting('visit_bonus_points','100'::jsonb))::text::int, 'visit', v_inv, 'مكافأة ' || (v_c.visits + 1) || ' زيارة'); end if;
    end if;
  end if;
  if p_appointment is not null then perform p15_complete_ticket(p_appointment); end if;
  return v_inv;
end $function$;

CREATE OR REPLACE FUNCTION public.checkout_invoice(p_customer bigint, p_barber uuid, p_items jsonb, p_discount_pct numeric, p_method text, p_appointment bigint DEFAULT NULL::bigint, p_redemption bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; v_inv bigint; v_sub numeric := 0; v_disc numeric; v_total numeric; v_name text; v_price numeric; v_qty int; v_max numeric;
        v_rd loyalty_redemptions; v_rw loyalty_rewards; v_rdisc numeric := 0; v_c customers; v_mult numeric; v_pts int; v_every int; v_ass uuid; v_apct numeric;
begin
  if not has_perm('use_pos') then raise exception 'غير مصرح'; end if;
  v_max := (setting('max_discount_pct','20'::jsonb))::text::numeric;
  if not is_mgr() and coalesce(p_discount_pct,0) > v_max then raise exception 'أقصى خصم مسموح % بالمية', v_max; end if;
  if p_appointment is not null then
    if p_customer is null then select a.customer_id into p_customer from appointments a where a.id = p_appointment; end if;
    if p_barber is null then select a.barber_id into p_barber from appointments a where a.id = p_appointment; end if;
  end if;
  insert into invoices(customer_id,barber_id,appointment_id,subtotal,discount,total,payment_method) values (p_customer,p_barber,p_appointment,0,0,0,p_method) returning id into v_inv;
  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := coalesce((it->>'qty')::int,1); v_ass := null; v_apct := null;
    if it->>'type' = 'service' then select name, price into v_name, v_price from services where id = (it->>'id')::bigint;
      if nullif(it->>'assistant','') is not null then
        if p_barber is null then raise exception 'اختار الحلاق الأول قبل ما تحدد مساعد'; end if;
        select pr.id, pr.commission_pct into v_ass, v_apct from profiles pr where pr.id = (it->>'assistant')::uuid and pr.role = 'assistant';
        if v_ass is null then raise exception 'المساعد غير صالح'; end if;
      end if;
    else
      update products set stock = stock - v_qty where id = (it->>'id')::bigint returning name, price into v_name, v_price;
      insert into stock_movements(product_id,qty,reason) values ((it->>'id')::bigint,-v_qty,'sale');
    end if;
    insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price,assistant_id,assistant_pct) values (v_inv,it->>'type',(it->>'id')::bigint,v_name,v_qty,v_price,v_ass,v_apct);
    v_sub := v_sub + v_price * v_qty;
  end loop;
  v_disc := v_sub * coalesce(p_discount_pct,0) / 100;
  if p_redemption is not null then
    select * into v_rd from loyalty_redemptions where id = p_redemption and status = 'active' and customer_id = p_customer;
    if v_rd.id is null then raise exception 'الكوبون غير صالح'; end if;
    select * into v_rw from loyalty_rewards where id = v_rd.reward_id;
    v_rdisc := case v_rw.kind when 'amount' then v_rw.value when 'pct' then v_sub * v_rw.value / 100
      else coalesce((select ii.unit_price from invoice_items ii where ii.invoice_id = v_inv and ii.item_type = 'service' and ii.item_id = v_rw.service_id limit 1), 0) end;
    if v_rdisc <= 0 then raise exception 'الكوبون ده مش مناسب للفاتورة دي'; end if;
    update loyalty_redemptions set status = 'used', used_at = now(), invoice_id = v_inv where id = p_redemption;
  end if;
  v_disc := least(v_sub, v_disc + v_rdisc); v_total := v_sub - v_disc;
  update invoices set subtotal = v_sub, discount = v_disc, total = v_total where id = v_inv;
  -- خصم المساعد: نسبته (اللي اتسجلت وقت الفاتورة) من اللي الزبون دفعه فعلًا على الخدمة دي (بعد توزيع الخصم)
  update invoice_items set assistant_cut = round(unit_price * qty * (case when v_sub > 0 then (v_sub - v_disc) / v_sub else 0 end) * assistant_pct / 100, 2)
   where invoice_id = v_inv and assistant_id is not null;
  if p_customer is not null then
    select * into v_c from customers where id = p_customer;
    select t.mult into v_mult from loyalty_tier(v_c.lifetime_points) t;
    v_pts := floor(v_total / greatest((setting('points_per_currency','10'::jsonb))::text::numeric, 1) * v_mult)::int;
    if v_pts > 0 then perform add_points(p_customer, v_pts, 'purchase', v_inv, 'فاتورة'); end if;
    update customers set visits = visits + 1 where id = p_customer;
    v_every := greatest((setting('visit_bonus_every','5'::jsonb))::text::int, 1);
    if (v_c.visits + 1) % v_every = 0 then
      perform add_points(p_customer, (setting('visit_bonus_points','100'::jsonb))::text::int, 'visit', v_inv, 'مكافأة ' || (v_c.visits + 1) || ' زيارة'); end if;
  end if;
  if p_appointment is not null then perform p15_complete_ticket(p_appointment); end if;
  return v_inv;
end $function$;

drop function if exists public.staff_schedule(uuid);

CREATE OR REPLACE FUNCTION public.staff_schedule(p_staff uuid)
 RETURNS TABLE(id bigint, day date, period text, ticket_no integer, ticket_code text, status appt_status, called boolean, eta text, finished boolean, customer_name text, customer_phone text, services text, total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (is_mgr() or has_perm('manage_appts') or (auth.uid() = p_staff and has_perm('view_own_schedule'))) then raise exception 'غير مصرح'; end if;
  return query
    select a.id, a.day, a.period, a.ticket_no, a.ticket_code, a.status, a.called_at is not null, a.eta, a.finished_at is not null, c.name,
      case when is_mgr() or has_perm('view_customer_phone') then c.phone else null end,
      coalesce((select string_agg(s.name, ' + ') from appointment_services x join services s on s.id = x.service_id where x.appointment_id = a.id), ''),
      coalesce((select sum(s.price) from appointment_services x join services s on s.id = x.service_id where x.appointment_id = a.id), 0)
    from appointments a join customers c on c.id = a.customer_id
    where a.barber_id = p_staff and a.day >= (now() at time zone my_tz())::date and a.status::text not in ('cancelled','done','no_show')
    order by a.day, case a.period when 'night' then 0 when 'morning' then 1 when 'afternoon' then 2 else 3 end, a.ticket_no;
end $function$;

revoke all on function public.staff_schedule(uuid) from public, anon;
grant execute on function public.staff_schedule(uuid) to authenticated;

drop function if exists public.queue_status(bigint);

CREATE OR REPLACE FUNCTION public.queue_status(p_id bigint)
 RETURNS TABLE(id bigint, day date, period text, ticket_no integer, ticket_code text, status appt_status, called boolean, eta text, finished boolean, barber_name text, current_no integer, ahead bigint, est_min bigint, total numeric, services text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.id, a.day, a.period, a.ticket_no, a.ticket_code, a.status, a.called_at is not null, a.eta, a.finished_at is not null, pr.full_name,
    (select x.ticket_no from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.status = 'in_service' order by x.ticket_no limit 1),
    (select count(*) from appointments x where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and x.ticket_no < a.ticket_no and x.status in ('upcoming','checked_in','in_service')),
    coalesce((select sum(sv.duration_min) from appointments x join appointment_services s2 on s2.appointment_id = x.id join services sv on sv.id = s2.service_id
      where x.barber_id = a.barber_id and x.day = a.day and x.period = a.period and x.ticket_no < a.ticket_no and x.status in ('upcoming','checked_in','in_service')), 0),
    coalesce((select sum(sv.price) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), 0),
    coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), '')
  from appointments a left join profiles pr on pr.id = a.barber_id
  where a.id = p_id and a.customer_id in (select c.id from customers c where c.user_id = auth.uid()) $function$;

revoke all on function public.queue_status(bigint) from public, anon;
grant execute on function public.queue_status(bigint) to authenticated;

CREATE OR REPLACE FUNCTION public.p11_queue_core(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       and a.period::text is not distinct from m.period::text
       and a.ticket_no < m.ticket_no
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
   where a.day = m.day and a.period::text is not distinct from m.period::text
     and a.status::text = 'in_service';
  select full_name into v_bname from profiles where id = m.barber_id;

  return jsonb_build_object(
    'id', m.id, 'status', m.status::text, 'day', m.day, 'period', m.period::text,
    'ticket_no', m.ticket_no, 'ticket_code', m.ticket_code, 'barber_id', m.barber_id, 'barber_name', v_bname,
    'ahead', v_ahead, 'est_wait_min', round(v_wait), 'est_service_min', round(p11_est_minutes(m.id)),
    'current_no', v_cur, 'called', m.called_at is not null,
    'near_turn', (m.status::text = 'upcoming' and v_ahead <= v_th and v_th >= 0),
    'near_turn_threshold', v_th);
end $function$;

CREATE OR REPLACE FUNCTION public.p11_apply_display(j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not p11_cfg_bool('show_queue_number', true)   then j := j - 'ticket_no' - 'ticket_code' - 'current_no'; end if;
  if not p11_cfg_bool('show_people_ahead', true)   then j := j - 'ahead'; end if;
  if not p11_cfg_bool('show_estimated_wait', true) then j := j - 'est_wait_min'; end if;
  return j;
end $function$;


-- ---------- 8) شاشات الواجهة (RPC بدل القراءة المباشرة: الحلاق ما عندوش صلاحية قراءة جدول الحجوزات) ----------
-- طابور الحلاق (طابوره هو أو أي حلاق للمدير/الكاشير) — يشمل المتخطّين عشان يقدر يرجّعهم
create or replace function public.my_queue(p_barber uuid default null, p_day date default null)
returns table(id bigint, day date, period text, ticket_no int, ticket_code text, queue_no int, status appt_status, called boolean,
              call_count int, eta text, finished boolean, customer_name text, services text, sort_at timestamptz, skip_reason text, transfer_count int)
language sql stable security definer set search_path = public as $$
  select a.id, a.day, a.period, a.ticket_no, a.ticket_code, a.queue_no, a.status, a.called_at is not null, a.call_count, a.eta, a.finished_at is not null,
         c.name,
         coalesce((select string_agg(sv.name, ' + ') from appointment_services x join services sv on sv.id = x.service_id where x.appointment_id = a.id), ''),
         a.sort_at, a.skip_reason, a.transfer_count
    from appointments a left join customers c on c.id = a.customer_id
   where a.day = coalesce(p_day, (now() at time zone my_tz())::date)
     and a.status::text in ('upcoming', 'checked_in', 'in_service', 'no_show')
     and ((coalesce(p_barber, auth.uid()) = auth.uid() and has_perm('view_own_schedule') and a.barber_id = auth.uid())
          or ((is_mgr() or has_perm('manage_appts')) and (p_barber is null or a.barber_id = p_barber)))
   order by (a.status::text = 'no_show'), a.sort_at, a.id
$$;
revoke all on function public.my_queue(uuid, date) from public, anon;
grant execute on function public.my_queue(uuid, date) to authenticated;

-- طلبات النقل المعلّقة اللي المستخدم يقدر يقرر فيها (حلاق الطلب/الجديد أو المدير/الكاشير)
create or replace function public.pending_transfers()
returns table(id bigint, appointment_id bigint, old_code text, from_barber uuid, from_name text, to_barber uuid, to_name text, customer_name text, reason text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select t.id, t.appointment_id, t.old_code, t.from_barber, pf.full_name, t.to_barber, pt.full_name, c.name, t.reason, t.created_at
    from ticket_transfers t
    join appointments a on a.id = t.appointment_id
    left join customers c on c.id = a.customer_id
    left join profiles pf on pf.id = t.from_barber
    left join profiles pt on pt.id = t.to_barber
   where t.status = 'pending' and (is_mgr() or has_perm('manage_appts') or auth.uid() in (t.from_barber, t.to_barber))
   order by t.created_at
$$;
revoke all on function public.pending_transfers() from public, anon;
grant execute on function public.pending_transfers() to authenticated;


-- ---------- للتراجع ----------
-- (الأعمدة والجداول الجديدة إضافات؛ تقدر تسيبها. لإرجاع السلوك القديم أعد تشغيل تعريفات الدوال القديمة من نسخة احتياطية.)
-- drop trigger if exists zz_p15_guard on public.appointments; drop trigger if exists zz_p15_audit on public.appointments;
