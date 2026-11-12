-- حجز لشخص تابع (ابن/أخ... من غير موبايل): كل تابع ملف عميل لوحده (نقاطه وزياراته ليه) مربوط بصاحب الحساب.
-- آمن للتكرار. مفيش بيانات بتتمسح. شغّله في Supabase SQL Editor.
alter table public.customers add column if not exists guardian_id bigint references public.customers(id) on delete restrict;
create index if not exists customers_guardian_idx on public.customers(guardian_id) where guardian_id is not null;

create or replace function public.p_dep_chk() returns trigger language plpgsql as $$
begin
  if new.guardian_id is not null then
    if new.guardian_id = new.id then raise exception 'مينفعش يتبع نفسه'; end if;
    if exists (select 1 from customers g where g.id = new.guardian_id and g.guardian_id is not null) then raise exception 'مينفعش تابع لتابع'; end if;
  end if;
  return new;
end $$;
drop trigger if exists p_dep_chk on public.customers;
create trigger p_dep_chk before insert or update of guardian_id on public.customers for each row execute function public.p_dep_chk();

-- التابعين بتوعي
create or replace function public.my_dependents()
returns table(id bigint, name text, points integer, visits integer)
language sql stable security definer set search_path to 'public' as $$
  select d.id, d.name, d.points, d.visits from customers d join customers g on g.id = d.guardian_id
   where g.user_id = auth.uid() order by d.id $$;

create or replace function public.add_dependent(p_name text)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_g bigint; v_n text := btrim(coalesce(p_name, '')); v_id bigint;
begin
  select c.id into v_g from customers c where c.user_id = auth.uid() and c.guardian_id is null;
  if v_g is null then raise exception 'سجّل بياناتك الأول'; end if;
  if char_length(v_n) < 2 or char_length(v_n) > 60 then raise exception 'اكتب اسمه'; end if;
  if (select count(*) from customers where guardian_id = v_g) >= 8 then raise exception 'وصلت الحد الأقصى للأشخاص التابعين (8)'; end if;
  select id into v_id from customers where guardian_id = v_g and lower(name) = lower(v_n);
  if v_id is not null then return v_id; end if;
  insert into customers(name, guardian_id) values (v_n, v_g) returning id into v_id;
  return v_id;
end $$;

create or replace function public.remove_dependent(p_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from customers d join customers g on g.id = d.guardian_id where d.id = p_id and g.user_id = auth.uid()) then raise exception 'مش تابع ليك'; end if;
  if exists (select 1 from appointments where customer_id = p_id) or exists (select 1 from invoices where customer_id = p_id) then
    raise exception 'مينفعش يتمسح لأن له حجوزات أو فواتير'; end if;
  delete from customers where id = p_id;
end $$;

-- حجز العميل: p_for = تابع (اختياري). بنمسح النسخة القديمة عشان مفيش لبس في الاسم.
drop function if exists public.book_ticket(uuid, date, text, bigint[]);
create or replace function public.book_ticket(p_barber uuid, p_day date, p_period text, p_services bigint[], p_for bigint default null)
returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare v_c bigint; v_e time; v_tz text := my_tz();
begin
  if not coalesce((setting('booking_open','true'::jsonb))::text::boolean, true) then raise exception 'الحجز متوقف حاليًا'; end if;
  select c.id into v_c from customers c where c.user_id = auth.uid();
  if v_c is null then raise exception 'سجّل بياناتك الأول'; end if;
  if p_for is not null then
    if not exists (select 1 from customers d where d.id = p_for and d.guardian_id = v_c) then raise exception 'الشخص ده مش تابع ليك'; end if;
    v_c := p_for;
  end if;
  if p_day < (now() at time zone v_tz)::date then raise exception 'التاريخ قديم'; end if;
  select r.e into v_e from period_range(p_period) r;
  if p_day = (now() at time zone v_tz)::date and (now() at time zone v_tz)::time >= v_e then raise exception 'الفترة دي خلصت'; end if;
  if exists (select 1 from appointments a where a.customer_id = v_c and a.day = p_day and a.status in ('upcoming','checked_in','in_service')) then
    raise exception 'عنده حجز نشط في اليوم ده'; end if;
  if (select count(*) from appointments a where a.customer_id = v_c and a.status::text = 'no_show' and a.day >= (now() at time zone v_tz)::date - 30) >= 2 then
    raise exception 'الحجز الأونلاين موقوف بسبب غياب متكرر. كلّم الصالون'; end if;
  perform p20_guard_late(p_barber, p_day, p_period, p_services);
  return make_ticket(v_c, p_barber, p_day, p_period, p_services, 'upcoming'::appt_status);
end $function$;

-- حجوزات التابعين النشطة (للعرض والإلغاء)
create or replace function public.my_family_tickets()
returns table(id bigint, ticket_no integer, day date, period text, status text, person text, barber text)
language sql stable security definer set search_path to 'public' as $$
  select a.id, a.ticket_no, a.day, a.period, a.status::text, d.name, pr.full_name
    from appointments a join customers d on d.id = a.customer_id join customers g on g.id = d.guardian_id
    left join profiles pr on pr.id = a.barber_id
   where g.user_id = auth.uid() and a.status in ('upcoming','checked_in','in_service') order by a.id $$;

-- إلغاء الحجز: بتاعي أو بتاع تابع ليا
create or replace function public.cancel_my_appt(p_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $function$
begin
  update appointments a set status = 'cancelled'
   where a.id = p_id and a.status = 'upcoming' and a.called_at is null
     and a.customer_id in (select c.id from customers c where c.user_id = auth.uid()
                           or c.guardian_id in (select g.id from customers g where g.user_id = auth.uid()));
  if not found then raise exception 'مينفعش تلغي الحجز ده'; end if;
end $function$;

-- حجز إداري لتابع عميل (الكاشير/المدير): بموبايل صاحب الحساب + اسم التابع، والتابع بيتفتح له ملف لو مش موجود
create or replace function public.admin_book_dependent(p_phone text, p_dep_name text, p_barber uuid, p_day date, p_period text, p_services bigint[])
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  v_ph text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g'); v_n text := btrim(coalesce(p_dep_name,''));
  v_g bigint; v_d bigint; v_e time; v_tz text := my_tz(); r jsonb; v_t record; v_old bigint;
  v_today date := biz_today();
  v_ahead int := greatest(coalesce((setting('days_ahead','5'::jsonb) #>> '{}')::int, 5), 1);
  v_off int := coalesce((setting('weekly_off','5'::jsonb) #>> '{}')::int, -1);
begin
  if not (p11_is_manager() or p11_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  if char_length(v_n) < 2 or char_length(v_n) > 60 then raise exception 'اكتب اسم التابع'; end if;
  select c.id into v_g from customers c where c.phone = v_ph and c.guardian_id is null;
  if v_g is null then raise exception 'مفيش عميل بالرقم ده، سجّله الأول'; end if;
  select id into v_d from customers where guardian_id = v_g and lower(name) = lower(v_n);
  if v_d is null then
    if (select count(*) from customers where guardian_id = v_g) >= 8 then raise exception 'وصل الحد الأقصى للأشخاص التابعين (8)'; end if;
    insert into customers(name, guardian_id) values (v_n, v_g) returning id into v_d;
  end if;
  select a.id into v_old from appointments a where a.customer_id = v_d and a.status in ('upcoming','checked_in','in_service') order by a.id limit 1;
  if v_old is null then
    if p_period is null or p_period not in ('morning','afternoon','evening','night') then raise exception 'اختار الفترة'; end if;
    if p_day is null or p_day < v_today or p_day > v_today + v_ahead - 1 then raise exception 'التاريخ ده مش متاح للحجز'; end if;
    if extract(dow from p_day)::int = v_off then raise exception 'الصالون إجازة في اليوم ده'; end if;
    select r2.e into v_e from period_range(p_period) r2;
    if p_day = v_today and (now() at time zone v_tz)::time >= v_e then raise exception 'الفترة دي خلصت'; end if;
    perform p20_guard_late(p_barber, p_day, p_period, p_services);
  end if;
  r := p14_make_ticket(v_d, p_barber, p_day, p_period, p_services, 'upcoming'::appt_status, null);
  select a.id, a.ticket_no, a.day, a.period, a.status::text as st, pr.full_name as bn into v_t
    from appointments a left join profiles pr on pr.id = a.barber_id where a.id = (r->>'id')::bigint;
  return jsonb_build_object('ok', true, 'existing', coalesce((r->>'existing')::boolean, false), 'dependent_id', v_d,
    'ticket', jsonb_build_object('id', v_t.id, 'no', v_t.ticket_no, 'day', v_t.day, 'period', v_t.period, 'barber', v_t.bn, 'status', v_t.st));
end $function$;

grant execute on function public.my_dependents(), public.add_dependent(text), public.remove_dependent(bigint),
  public.my_family_tickets(), public.book_ticket(uuid, date, text, bigint[], bigint), public.cancel_my_appt(bigint),
  public.admin_book_dependent(text, text, uuid, date, text, bigint[]) to authenticated;
