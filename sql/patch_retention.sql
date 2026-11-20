-- المرحلة ب (دخل): رجوع العملاء + تذكير الزيارة القادمة + تحكم العميل في الرسائل التسويقية.
-- 1) customer_prefs: العميل يقفل/يفتح استقبال العروض من التطبيق (الافتراضي: مفتوح، وسهل يتقفل). تذكيره اللي طلبه بنفسه بيوصله دايمًا.
-- 2) next_visit_reminders: العميل يختار «ذكّرني بعد كام يوم»، والنظام يبعتله إشعار في اليوم، ويقيس هل رجع فعلًا.
-- 3) retention_report: مين بقاله فترة ماجاش + معدل الرجوع خلال 30/60 يوم + فعالية رسائل الاستعادة. قراءة فقط.
-- 4) winback_log: تسجيل كل رسالة استعادة (بزرار واتساب) عشان ما نكررش على نفس العميل ونقيس النتيجة.
-- ملحوظة أمانة: بيانات الفواتير المرتبطة بعملاء بتبدأ من أكتوبر 2026، فمعدلات الرجوع هتبقى أدق مع الوقت.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّر أي بيانات قديمة.

create table if not exists public.customer_prefs (
  customer_id bigint primary key references public.customers(id) on delete cascade,
  marketing_ok boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.customer_prefs enable row level security;
revoke all on public.customer_prefs from public, anon, authenticated;

create table if not exists public.next_visit_reminders (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  remind_on date not null,
  status text not null default 'pending' check (status in ('pending', 'sent', 'converted', 'cancelled')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  converted_at timestamptz
);
create unique index if not exists nvr_one_pending on public.next_visit_reminders(customer_id) where status = 'pending';
alter table public.next_visit_reminders enable row level security;
revoke all on public.next_visit_reminders from public, anon, authenticated;

create table if not exists public.winback_log (
  id bigint generated always as identity primary key,
  customer_id bigint not null references public.customers(id) on delete cascade,
  sent_at timestamptz not null default now(),
  sent_by uuid,
  days_away int
);
create index if not exists winback_log_cust on public.winback_log(customer_id, sent_at desc);
alter table public.winback_log enable row level security;
revoke all on public.winback_log from public, anon, authenticated;

-- ===== جهة العميل =====
create or replace function public.my_prefs()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('marketing_ok', coalesce((select marketing_ok from customer_prefs where customer_id = c.id), true));
end $$;

create or replace function public.my_prefs_set(p_marketing boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  insert into customer_prefs(customer_id, marketing_ok) values (c.id, coalesce(p_marketing, true))
    on conflict (customer_id) do update set marketing_ok = excluded.marketing_ok, updated_at = now();
end $$;

create or replace function public.my_next_visit()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare c customers; v_gap int; v_p next_visit_reminders; v_last timestamptz;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  select round(avg(g))::int into v_gap from (
    select extract(epoch from (created_at - lag(created_at) over (order by created_at))) / 86400 g from invoices where customer_id = c.id) x where g >= 1;
  select max(created_at) into v_last from invoices where customer_id = c.id;
  select * into v_p from next_visit_reminders where customer_id = c.id and status = 'pending';
  return jsonb_build_object('suggested', least(greatest(coalesce(v_gap, 21), 7), 60), 'last_visit', v_last,
    'pending', case when v_p.id is not null then jsonb_build_object('on', v_p.remind_on) end);
end $$;

create or replace function public.my_next_visit_set(p_days int)
returns date language plpgsql security definer set search_path = public, pg_temp as $$
declare c customers; v_on date;
begin
  select * into c from customers where user_id = auth.uid() limit 1;
  if not found then raise exception 'غير مصرح'; end if;
  if p_days is null or p_days not between 5 and 90 then raise exception 'اختار مدة من 5 لـ 90 يوم'; end if;
  v_on := (now() at time zone my_tz())::date + p_days;
  update next_visit_reminders set status = 'cancelled' where customer_id = c.id and status = 'pending';
  insert into next_visit_reminders(customer_id, remind_on) values (c.id, v_on);
  return v_on;
end $$;

create or replace function public.my_next_visit_cancel()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update next_visit_reminders set status = 'cancelled'
   where status = 'pending' and customer_id in (select id from customers where user_id = auth.uid());
end $$;

-- ===== التنفيذ الدوري (كل ساعة؛ بيبعت من الساعة 11 صباحًا بتوقيت الصالون) =====
create or replace function public.next_visit_run()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; v_uid uuid; n int := 0; v_today date := (now() at time zone my_tz())::date;
begin
  -- قياس الرجوع: زيارة بعد إرسال التذكير (خلال 14 يوم)
  update next_visit_reminders x set status = 'converted', converted_at = now()
   where x.status = 'sent' and exists (select 1 from invoices i where i.customer_id = x.customer_id and i.created_at > x.sent_at and i.created_at < x.sent_at + interval '14 days');
  if (now() at time zone my_tz())::time < time '11:00' then return 0; end if;
  for r in select x.id, x.customer_id, c.user_id from next_visit_reminders x join customers c on c.id = x.customer_id
            where x.status = 'pending' and x.remind_on <= v_today
  loop
    insert into customer_notifications(customer_id, kind, title, body)
      values (r.customer_id, 'next_visit', 'ميعاد حلاقتك الجاية ✂️', 'عدّى وقت من آخر زيارة. احجز دورك النهارده من التطبيق.');
    if r.user_id is not null then
      begin perform push_send(array[r.user_id], 'ميعاد حلاقتك الجاية ✂️', 'احجز دورك النهارده من التطبيق', 'book', 'nextvisit_' || r.id, false);
      exception when others then null;
      end;
    end if;
    update next_visit_reminders set status = 'sent', sent_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.next_visit_run() from public, anon, authenticated;
grant execute on function public.next_visit_run() to service_role;

-- ===== جهة الإدارة =====
create or replace function public.retention_report(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_days int := least(greatest(coalesce(p_days, 30), 7), 365); v_res jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  with v as (select customer_id, created_at, lag(created_at) over (partition by customer_id order by created_at) prev from invoices where customer_id is not null),
  per as (select customer_id, count(*) n, min(created_at) first_at, max(created_at) last_at from v group by customer_id),
  gaps as (select extract(epoch from (created_at - prev)) / 86400 g from v where prev is not null and created_at - prev >= interval '12 hours'),
  sec2 as (select p.customer_id, p.first_at, (select min(i.created_at) from invoices i where i.customer_id = p.customer_id and i.created_at > p.first_at + interval '12 hours') sec_at from per p),
  top as (select distinct on (i.customer_id) i.customer_id, ii.name from invoices i join invoice_items ii on ii.invoice_id = i.id and ii.item_type = 'service' and ii.item_id <> 0
           where i.customer_id is not null group by i.customer_id, ii.name order by i.customer_id, count(*) desc, ii.name),
  lap as (
    select c.id, c.name, c.phone, p.last_at, p.n, floor(extract(epoch from (now() - p.last_at)) / 86400)::int days_away, t.name top_service,
           coalesce(cp.marketing_ok, true) marketing_ok,
           (select max(w.sent_at) from winback_log w where w.customer_id = c.id) last_contact,
           exists (select 1 from next_visit_reminders r where r.customer_id = c.id and r.status = 'pending') has_reminder
      from per p join customers c on c.id = p.customer_id left join top t on t.customer_id = c.id left join customer_prefs cp on cp.customer_id = c.id
     where p.last_at < now() - make_interval(days => v_days))
  select jsonb_build_object(
    'days', v_days,
    'customers', (select count(*) from per),
    'active', (select count(*) from per where last_at >= now() - make_interval(days => v_days)),
    'lapsed', (select count(*) from lap), 'lapsed_60', (select count(*) from per where last_at < now() - interval '60 days'),
    'avg_gap_days', (select round(avg(g)::numeric, 1) from gaps),
    'median_gap_days', (select round((percentile_cont(0.5) within group (order by g))::numeric, 1) from gaps),
    'return30', jsonb_build_object('base', (select count(*) from sec2 where first_at < now() - interval '30 days'),
        'returned', (select count(*) from sec2 where first_at < now() - interval '30 days' and sec_at <= first_at + interval '30 days')),
    'return60', jsonb_build_object('base', (select count(*) from sec2 where first_at < now() - interval '60 days'),
        'returned', (select count(*) from sec2 where first_at < now() - interval '60 days' and sec_at <= first_at + interval '60 days')),
    'winback', jsonb_build_object('sent', (select count(distinct customer_id) from winback_log where sent_at > now() - interval '90 days'),
        'returned', (select count(distinct w.customer_id) from winback_log w where w.sent_at > now() - interval '90 days'
            and exists (select 1 from invoices i where i.customer_id = w.customer_id and i.created_at > w.sent_at and i.created_at < w.sent_at + interval '30 days'))),
    'next_visit', jsonb_build_object('created', (select count(*) from next_visit_reminders), 'sent', (select count(*) from next_visit_reminders where status in ('sent', 'converted')),
        'converted', (select count(*) from next_visit_reminders where status = 'converted')),
    'data_since', (select min(created_at) from invoices where customer_id is not null),
    'list', coalesce((select jsonb_agg(to_jsonb(l) order by l.last_at desc) from (select * from lap order by last_at desc limit 150) l), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;

create or replace function public.winback_mark(p_customer bigint, p_days int default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() and not p11_perm('manage_appts') then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from customers where id = p_customer) then raise exception 'العميل غير موجود'; end if;
  insert into winback_log(customer_id, sent_by, days_away) values (p_customer, auth.uid(), p_days);
end $$;

do $$
declare f text;
begin
  foreach f in array array['my_prefs()', 'my_prefs_set(boolean)', 'my_next_visit()', 'my_next_visit_set(integer)', 'my_next_visit_cancel()',
                           'retention_report(integer)', 'winback_mark(bigint,integer)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  if exists (select 1 from cron.job where jobname = 'next-visit-run') then perform cron.unschedule('next-visit-run'); end if;
  perform cron.schedule('next-visit-run', '20 * * * *', 'select public.next_visit_run()');
end $$;

do $$
declare t text;
begin
  if to_regprocedure('public.p20_audit()') is null then return; end if;
  foreach t in array array['customer_prefs', 'next_visit_reminders', 'winback_log'] loop
    if not exists (select 1 from pg_trigger where tgname = 'zz_audit' and tgrelid = to_regclass('public.' || t)) then
      execute format('create trigger zz_audit after insert or update or delete on public.%I for each row execute function public.p20_audit()', t);
    end if;
  end loop;
end $$;

notify pgrst, 'reload schema';
