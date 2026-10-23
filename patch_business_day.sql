-- patch_business_day.sql — "يوم العمل": المالك/المدير هو اللي يفتح اليوم ويقفله (مش الساعة 12 بالليل)
-- • فتح اليوم = زرار. يوم العمل بيفضل شغّال (حتى بعد 12) لحد ما تقفله.
-- • قفل اليوم = جرد الدرج (كاش/كارت/محفظة) من شاشة الخزنة: اليوم ما بيتقفلش غير لما الجرد يتسجّل.
-- • "النهارده" في الدور والحجز والكاشير والدرج = يوم العمل المفتوح. لو مفيش يوم مفتوح بيرجع لتاريخ النهارده العادي (مفيش حاجة بتتمنع).
-- • مفيش حركة قديمة بتتعدّل. الحضور والرواتب والأجور بتفضل على التاريخ العادي زي ما هي.
create table if not exists public.business_days (
  day date primary key,
  opened_at timestamptz not null default now(),
  opened_by uuid,
  closed_at timestamptz,
  closed_by uuid
);
alter table public.business_days enable row level security;   -- الوصول بالدوال بس
create unique index if not exists uq_business_one_open on public.business_days ((true)) where closed_at is null;

-- يوم العمل الحالي (أو تاريخ النهارده لو مفيش يوم مفتوح)
create or replace function public.biz_today() returns date
language sql stable security definer set search_path to 'public' as $$
  select coalesce((select day from business_days where closed_at is null), (now() at time zone my_tz())::date)
$$;

-- بداية فترة يوم العمل: أول يوم = أبكر من فتحه أو بداية تاريخه، وبعده = وقت قفل اللي قبله (اللي يحصل وهو مقفول يتحسب على اللي بعده)
create or replace function public.p24b_start(p_day date) returns timestamptz
language sql stable security definer set search_path to 'public' as $$
  select coalesce((select max(c.closed_at) from business_days c where c.closed_at is not null and c.day < p_day),
                  (select least(b.opened_at, (b.day::timestamp at time zone my_tz())) from business_days b where b.day = p_day))
$$;

-- هل اللحظة دي تابعة لليوم ده (يوم عمل لو موجود، وإلا التاريخ العادي بشرط ما تكونش جوه يوم عمل تاني)
create or replace function public.p24b_in_day(ts timestamptz, p_day date, tz text) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select case
    when exists (select 1 from business_days b where b.day = p_day)
      then ts >= p24b_start(p_day) and ts < coalesce((select b.closed_at from business_days b where b.day = p_day), 'infinity'::timestamptz)
    else (ts at time zone tz)::date = p_day
         and not exists (select 1 from business_days b where ts >= p24b_start(b.day) and ts < coalesce(b.closed_at, 'infinity'::timestamptz))
  end
$$;

-- حالة اليوم للتطبيقات (الموظفين وصفحة الحجز)
create or replace function public.business_day_state() returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select case when b.day is null
    then jsonb_build_object('open', false, 'day', (now() at time zone my_tz())::date, 'calendar', (now() at time zone my_tz())::date)
    else jsonb_build_object('open', true, 'day', b.day, 'opened_at', b.opened_at, 'window_from', p24b_start(b.day),
                            'calendar', (now() at time zone my_tz())::date)
  end
  from (select 1) x left join business_days b on b.closed_at is null
$$;
grant execute on function public.biz_today() to anon, authenticated;
grant execute on function public.business_day_state() to anon, authenticated;
revoke all on function public.p24b_start(date) from public, anon, authenticated;
revoke all on function public.p24b_in_day(timestamptz, date, text) from public, anon, authenticated;

-- فتح اليوم (مالك/مدير)
create or replace function public.open_business_day() returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v date := (now() at time zone my_tz())::date; o date;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select day into o from business_days where closed_at is null;
  if o is not null then raise exception 'فيه يوم مفتوح بالفعل (%). اقفله الأول من الخزنة.', o; end if;
  if exists (select 1 from cash_closings c where c.day = v) then raise exception 'يوم % اتقفل قبل كده (اتعمله جرد). لو عايز تفتحه امسح الجرد من الخزنة الأول.', v; end if;
  insert into business_days(day, opened_by) values (v, auth.uid())
    on conflict (day) do update set closed_at = null, closed_by = null, opened_by = auth.uid();
  return business_day_state();
end $$;
revoke all on function public.open_business_day() from public, anon;
grant execute on function public.open_business_day() to authenticated;

-- قفل اليوم بيحصل مع جرد الدرج (close_day): نضيف علامة القفل
do $$ declare d text; n text;
begin
  d := pg_get_functiondef('close_day(date,numeric,numeric,numeric,numeric,text)'::regprocedure);
  if position('p24b_close' in d) = 0 then
    n := replace(d, 'returning * into v_row;',
      'returning * into v_row;' || E'\n' ||
      '  update business_days set closed_at = now(), closed_by = auth.uid() where day = p_day and closed_at is null; /* p24b_close */');
    if n = d or position('p24b_close' in n) = 0 then raise exception 'close_day: anchor not found'; end if;
    execute n;
  end if;
  -- مسح جرد يوم = يتفتح اليوم تاني (لو مفيش يوم تاني مفتوح)
end $$;

-- أرقام الدرج حسب فترة يوم العمل (فواتير وسحب الموظفين بالوقت)
do $$ declare d text; n text;
begin
  d := pg_get_functiondef('day_figures(date)'::regprocedure);
  if position('p24b_in_day' in d) = 0 then
    n := replace(d, '(i.created_at at time zone v_tz)::date = p_day', 'p24b_in_day(i.created_at, p_day, v_tz)');
    n := replace(n, '(t.created_at at time zone v_tz)::date = p_day', 'p24b_in_day(t.created_at, p_day, v_tz)');
    if n = d or position('p24b_in_day' in n) = 0 then raise exception 'day_figures: anchor not found'; end if;
    execute n;
  end if;
end $$;

-- "النهارده" = يوم العمل في دوال الدور والحجز والكاشير
do $$ declare r record; d text; n text;
begin
  for r in select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('p16_today','my_queue','tickets_awaiting_payment','urgent_board','walk_in_ticket_v2',
                  'admin_urgent_ticket','request_urgent','return_ticket','staff_schedule','p11_appt_before_insert','p11_pick_barber',
                  'p13_progress','p14_book_core','p19_present','owner_dashboard') loop
    d := pg_get_functiondef(r.oid);
    n := replace(replace(d, '(now() at time zone my_tz())::date', 'biz_today()'), '(now() at time zone p11_tz())::date', 'biz_today()');
    if n <> d then execute n; end if;
  end loop;
end $$;
