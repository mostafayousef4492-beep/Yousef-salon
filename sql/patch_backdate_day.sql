-- فتح يوم عمل بتاريخ تختاره: كل الشغل الجديد (فواتير، مصروفات، سحب وضخ، سلف ومكافآت وخصومات،
-- مشتريات، صرف رواتب، نقاط، حركات مخزون) بيتسجل بتاريخ اليوم المفتوح مش بتاريخ النهارده الحقيقي.
-- الحضور والانصراف بيفضلوا بالوقت الحقيقي. بيتشغل مرة واحدة (آمن للتكرار).

-- يوم العمل "الطبيعي" دلوقتي: التاريخ بعد خصم 6 ساعات (الشغل لحد 6 الصبح لسه تبع إمبارح)
create or replace function public.biz_natural_day() returns date language sql stable
  set search_path = public as $$ select ((now() at time zone my_tz()) - interval '6 hours')::date $$;

-- عدد الأيام اللي بنرجّعها لورا: 0 لو مفيش يوم مفتوح أو اليوم المفتوح هو الطبيعي، وسالب لو اليوم المفتوح أقدم
create or replace function public.biz_shift_days() returns int language sql stable security definer
  set search_path = public as $$
  select coalesce((select least(0, b.day - biz_natural_day()) from business_days b where b.closed_at is null limit 1), 0) $$;

create or replace function public.biz_stamp(ts timestamptz) returns timestamptz language sql stable
  set search_path = public as $$
  select case when biz_shift_days() = 0 then ts
              else ((ts at time zone my_tz()) + biz_shift_days() * interval '1 day') at time zone my_tz() end $$;

-- تريجر: بيأرّخ السجل الجديد بتاريخ اليوم المفتوح (بس للسجلات اللي اتعملت دلوقتي، مش اللي بتاريخ قديم مقصود)
create or replace function public.trg_biz_stamp() returns trigger language plpgsql security definer
  set search_path = public as $$
declare sh int := biz_shift_days(); today date := (now() at time zone my_tz())::date; nat date := biz_natural_day(); od date; j jsonb; o jsonb; fresh boolean;
begin
  if sh = 0 then return new; end if;
  select day into od from business_days where closed_at is null limit 1;
  j := to_jsonb(new);
  fresh := (j->>'created_at') is null or ((j->>'created_at')::timestamptz between now() - interval '2 minutes' and now() + interval '2 minutes');
  if not fresh then return new; end if;
  o := jsonb_build_object('created_at', biz_stamp(coalesce(new.created_at, now())));
  if TG_TABLE_NAME = 'expenses' and (j->>'spent_on')::date in (today, nat) then o := o || jsonb_build_object('spent_on', od); end if;
  if TG_TABLE_NAME = 'cash_moves' and (j->>'day')::date in (today, nat) then o := o || jsonb_build_object('day', od); end if;
  if TG_TABLE_NAME = 'purchases' and (j->>'bought_on')::date in (today, nat) then o := o || jsonb_build_object('bought_on', od); end if;
  if TG_TABLE_NAME in ('supplier_payments','salary_payments') and (j->>'paid_on')::date in (today, nat) then o := o || jsonb_build_object('paid_on', od); end if;
  new := jsonb_populate_record(new, o);
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['invoices','expenses','cash_moves','staff_transactions','purchases','supplier_payments','salary_payments','loyalty_ledger','stock_movements'] loop
    execute format('drop trigger if exists a0_biz_stamp on public.%I', t);
    execute format('create trigger a0_biz_stamp before insert on public.%I for each row execute function public.trg_biz_stamp()', t);
  end loop;
end $$;

-- حالة اليوم: زوّدنا natural و backdated عشان الواجهة تعرض شريط التنبيه
create or replace function public.business_day_state() returns jsonb language sql stable security definer
  set search_path = public as $$
  select case when b.day is null
    then jsonb_build_object('open', false, 'day', (now() at time zone my_tz())::date, 'calendar', (now() at time zone my_tz())::date, 'natural', biz_natural_day(), 'backdated', false)
    else jsonb_build_object('open', true, 'day', b.day, 'opened_at', b.opened_at, 'window_from', p24b_start(b.day),
                            'calendar', (now() at time zone my_tz())::date, 'natural', biz_natural_day(), 'backdated', b.day < biz_natural_day())
  end
  from (select 1) x left join business_days b on b.closed_at is null $$;

-- فتح اليوم: التاريخ اختياري. من غير تاريخ = النهارده (زي الأول).
drop function if exists public.open_business_day();
create or replace function public.open_business_day(p_day date default null) returns jsonb language plpgsql security definer
  set search_path = public as $$
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
  return business_day_state();
end $$;
revoke all on function public.open_business_day(date) from public, anon;
grant execute on function public.open_business_day(date) to authenticated;

-- قفل اليوم: وقت القفل بيتأرّخ بنفس طريقة السجلات لو اليوم قديم
do $$
declare d text;
begin
  select pg_get_functiondef('public.close_day(date,numeric,numeric,numeric,numeric,text)'::regprocedure) into d;
  if d like '%p29_close_stamp%' then return; end if;
  if d not like '%update business_days set closed_at = now(), closed_by = auth.uid() where day = p_day and closed_at is null; /* p24b_close */%' then
    raise exception 'close_day مختلفة عن المتوقع، مش هعدّلها'; end if;
  d := replace(d, 'update business_days set closed_at = now(), closed_by = auth.uid() where day = p_day and closed_at is null; /* p24b_close */',
                  'update business_days set closed_at = biz_stamp(now()), closed_by = auth.uid() where day = p_day and closed_at is null; /* p24b_close */ /* p29_close_stamp */');
  execute d;
end $$;
