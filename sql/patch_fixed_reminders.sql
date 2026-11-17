-- مواعيد ثابتة للزباين: في اليوم والساعة اللي تحددهم السيستم يحجز دور للزبون (اختياري)
-- ويبعتلك إشعار فيه زرار واتساب برسالة تذكير جاهزة. آمن لو اتشغّل أكتر من مرة.
-- لا يغيّر أي حاجة قديمة. الحجز بيستخدم نفس دالة الحجز الأصلية (p14_book_core) بكل قواعدها.

create table if not exists fixed_reminders (
  id bigserial primary key,
  customer_id bigint not null references customers(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),      -- 0=الأحد ... 6=السبت
  at_time time not null,                                         -- وقت التنفيذ (بتوقيت الصالون)
  book boolean not null default true,                            -- يحجز دور ولا تذكير بس
  visit_offset smallint not null default 0 check (visit_offset between 0 and 4), -- الدور لأنهي يوم: 0=نفس اليوم
  period text check (period in ('morning','afternoon','evening','night')),
  barber_id uuid,
  services bigint[] not null default '{}',
  message text,
  active boolean not null default true,
  last_run_on date,
  created_at timestamptz not null default now(),
  created_by uuid
);
create table if not exists fixed_reminder_runs (
  id bigserial primary key,
  reminder_id bigint not null references fixed_reminders(id) on delete cascade,
  customer_id bigint not null,
  run_on date not null,
  message text not null,
  note text,
  ticket_id bigint,
  status text not null default 'pending' check (status in ('pending','sent','dismissed')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  sent_by uuid,
  unique (reminder_id, run_on)
);
create index if not exists fixed_runs_pending_idx on fixed_reminder_runs(status) where status = 'pending';
alter table fixed_reminders enable row level security;
alter table fixed_reminder_runs enable row level security;
drop policy if exists fixed_rem_read on fixed_reminders;
create policy fixed_rem_read on fixed_reminders for select using (is_mgr() or p11_perm('manage_appts'));
drop policy if exists fixed_runs_read on fixed_reminder_runs;
create policy fixed_runs_read on fixed_reminder_runs for select using (is_mgr() or p11_perm('manage_appts'));

-- إضافة/تعديل
create or replace function fixed_reminder_save(p_id bigint, p_customer bigint, p_weekday int, p_time time, p_book boolean,
  p_offset int, p_period text, p_barber uuid, p_services bigint[], p_message text, p_active boolean)
returns bigint language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not (is_mgr() or p11_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  if p_weekday is null or p_weekday not between 0 and 6 then raise exception 'اختار اليوم'; end if;
  if p_time is null then raise exception 'اكتب الساعة'; end if;
  if not exists (select 1 from customers where id = p_customer) then raise exception 'العميل غير موجود'; end if;
  if coalesce(p_book, true) and (p_period is null or p_period not in ('morning','afternoon','evening','night')) then raise exception 'اختار فترة الحجز'; end if;
  if p_message is not null and length(p_message) > 400 then raise exception 'الرسالة أطول من 400 حرف'; end if;
  if p_id is null then
    insert into fixed_reminders(customer_id, weekday, at_time, book, visit_offset, period, barber_id, services, message, active, created_by)
    values (p_customer, p_weekday, p_time, coalesce(p_book, true), coalesce(p_offset, 0), p_period, p_barber, coalesce(p_services, '{}'),
            nullif(trim(coalesce(p_message, '')), ''), coalesce(p_active, true), auth.uid()) returning id into v;
  else
    update fixed_reminders set customer_id = p_customer, weekday = p_weekday, at_time = p_time, book = coalesce(p_book, true),
      visit_offset = coalesce(p_offset, 0), period = p_period, barber_id = p_barber, services = coalesce(p_services, '{}'),
      message = nullif(trim(coalesce(p_message, '')), ''), active = coalesce(p_active, true)
     where id = p_id returning id into v;
    if v is null then raise exception 'الميعاد غير موجود'; end if;
  end if;
  return v;
end $$;

create or replace function fixed_reminder_delete(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_mgr() or p11_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  delete from fixed_reminders where id = p_id;
end $$;

create or replace function fixed_reminder_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (is_mgr() or p11_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'customer_id', r.customer_id, 'name', c.name, 'phone', c.phone,
        'weekday', r.weekday, 'time', to_char(r.at_time, 'HH24:MI'), 'book', r.book, 'offset', r.visit_offset, 'period', r.period,
        'barber_id', r.barber_id, 'services', r.services, 'message', r.message, 'active', r.active, 'last', r.last_run_on)
        order by r.weekday, r.at_time) from fixed_reminders r join customers c on c.id = r.customer_id), '[]'::jsonb),
    'pending', coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', c.name, 'phone', c.phone, 'message', u.message,
        'note', u.note, 'ticket_id', u.ticket_id, 'on', u.run_on) order by u.created_at) from fixed_reminder_runs u
        join customers c on c.id = u.customer_id where u.status = 'pending'), '[]'::jsonb));
end $$;

create or replace function fixed_run_mark(p_run bigint, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_mgr() or p11_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  if p_status not in ('sent','dismissed') then raise exception 'حالة غير صحيحة'; end if;
  update fixed_reminder_runs set status = p_status, sent_at = now(), sent_by = auth.uid() where id = p_run and status = 'pending';
end $$;

-- التنفيذ الدوري (بيشتغل من pg_cron كل 5 دقايق). بينفّذ كل ميعاد مرة واحدة في اليوم.
create or replace function fixed_reminder_run_due()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_now timestamp := now() at time zone my_tz(); v_today date := (now() at time zone my_tz())::date;
        v_day date; j jsonb; v_note text; v_tk bigint; v_msg text; v_run bigint; n int := 0; v_dn text;
        v_wd text[] := array['الأحد','الاتنين','التلات','الأربع','الخميس','الجمعة','السبت'];
begin
  for r in select fr.*, c.name as cname, c.phone as cphone from fixed_reminders fr join customers c on c.id = fr.customer_id
            where fr.active and fr.weekday = extract(dow from v_now)::int
              and v_now >= (v_today + fr.at_time)
              and (fr.last_run_on is null or fr.last_run_on < v_today)
  loop
    v_day := v_today + r.visit_offset; v_note := null; v_tk := null;
    v_dn := v_wd[extract(dow from v_day)::int + 1] || case when r.period is not null then ' ' || push_period(r.period) else '' end;
    if r.book then
      begin
        if coalesce(r.cphone, '') !~ '^01[0-9]{9}$' then raise exception 'رقم موبايل العميل ناقص أو غلط'; end if;
        j := p14_book_core(r.cname, r.cphone, r.barber_id, v_day, r.period, r.services, 'fixed');
        v_tk := (j->'ticket'->>'id')::bigint;
        v_note := case when coalesce((j->>'existing')::boolean, false) then 'عنده حجز نشط بالفعل (مش حجز جديد)' else 'اتحجز له دور رقم ' || coalesce(j->'ticket'->>'no', '?') end;
      exception when others then
        v_note := 'ماقدرتش أحجز: ' || sqlerrm;
      end;
    end if;
    v_msg := replace(replace(coalesce(r.message, 'أهلاً {name} 👋 بنفكرك بميعادك في صالون أبو يوسف ✂️ {day}'), '{name}', coalesce(r.cname, '')), '{day}', v_dn);
    insert into fixed_reminder_runs(reminder_id, customer_id, run_on, message, note, ticket_id)
      values (r.id, r.customer_id, v_today, v_msg, v_note, v_tk) on conflict (reminder_id, run_on) do nothing returning id into v_run;
    update fixed_reminders set last_run_on = v_today where id = r.id;
    if v_run is not null then
      n := n + 1;
      begin
        perform push_send(push_staff_ids(array['cashier'], 'manage_appts', null), 'ابعت تذكير لـ ' || coalesce(r.cname, 'عميل'),
          coalesce(v_note || ' · ', '') || 'دوس وابعتله الرسالة بالواتساب', 'fix', 'fixed_' || r.id, false);
      exception when others then null;
      end;
    end if;
    v_run := null;
  end loop;
  return n;
end $$;

-- الصلاحيات
do $$
declare f text;
begin
  foreach f in array array['fixed_reminder_save(bigint,bigint,integer,time without time zone,boolean,integer,text,uuid,bigint[],text,boolean)',
    'fixed_reminder_delete(bigint)', 'fixed_reminder_list()', 'fixed_run_mark(bigint,text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  revoke all on function fixed_reminder_run_due() from public, anon, authenticated;
  grant execute on function fixed_reminder_run_due() to service_role;
end $$;

-- الجدولة: كل 5 دقايق
do $$
begin
  if exists (select 1 from cron.job where jobname = 'fixed-reminders') then perform cron.unschedule('fixed-reminders'); end if;
  perform cron.schedule('fixed-reminders', '*/5 * * * *', 'select public.fixed_reminder_run_due()');
end $$;
