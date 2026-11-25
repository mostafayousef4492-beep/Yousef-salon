-- التشغيل الذاتي لكل الأقسام (اقتراحات): الحجوزات، الأعضاء والمتجر، المخزون، الخزنة وقفل اليوم، الفريق، العملاء، الديون، الكوفي.
-- بيحتاج patch_autopilot.sql متشغّل قبله. كل قسم له مفتاح وحدود منفصلة ومقفول افتراضيًا، وبيشتغل بس لو المفتاح الرئيسي «enabled» شغّال.
-- نظام «اقتراح فقط»: السيستم بيفحص كل 15 دقيقة ويطلّع اقتراحات للمالك والمدير (تم / تجاهل)، ومبيعملش أي حركة فلوس ولا بيغيّر بيانات.
-- آمن لو اتشغّل أكتر من مرة.

alter table public.autopilot_policy
  add column if not exists book_on boolean not null default false,
  add column if not exists book_late_min int not null default 30 check (book_late_min between 5 and 240),
  add column if not exists members_on boolean not null default false,
  add column if not exists mem_expiry_days int not null default 7 check (mem_expiry_days between 1 and 60),
  add column if not exists reserve_days int not null default 2 check (reserve_days between 1 and 30),
  add column if not exists stock_on boolean not null default false,
  add column if not exists cash_on boolean not null default false,
  add column if not exists cash_close_hour int not null default 23 check (cash_close_hour between 0 and 23),
  add column if not exists cash_diff_limit numeric not null default 50 check (cash_diff_limit >= 0),
  add column if not exists team_on boolean not null default false,
  add column if not exists team_open_hours int not null default 14 check (team_open_hours between 6 and 24),
  add column if not exists cust_on boolean not null default false,
  add column if not exists debt_on boolean not null default false,
  add column if not exists debt_days int not null default 7 check (debt_days between 1 and 90),
  add column if not exists cafe_on boolean not null default false;

create table if not exists public.autopilot_suggestions (
  id bigint generated always as identity primary key,
  area text not null,
  kind text not null,
  ref text not null,
  title text not null,
  body text,
  tab text,
  status text not null default 'open' check (status in ('open', 'done', 'dismissed')),
  created_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz
);
drop index if exists public.autopilot_sugg_open;
create unique index if not exists autopilot_sugg_once on public.autopilot_suggestions(kind, ref);
alter table public.autopilot_suggestions drop constraint if exists autopilot_suggestions_area_check;
alter table public.autopilot_suggestions add constraint autopilot_suggestions_area_check check (area in ('book', 'members', 'stock', 'cash', 'team', 'cust', 'debt', 'cafe'));
create index if not exists autopilot_sugg_recent on public.autopilot_suggestions(created_at desc);
alter table public.autopilot_suggestions enable row level security;
revoke all on public.autopilot_suggestions from public, anon, authenticated;

-- الفحص الدوري: بيطلّع اقتراحات بس. المرجع (ref) فيه التاريخ للحاجات المتكررة: الاقتراح بيتطلع مرة في اليوم بس، وحتى لو ضغطت تم أو تجاهل مبيرجعش نفس اليوم.
create or replace function public.autopilot_scan()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare pol autopilot_policy; v_tz text := my_tz(); v_today date; v_hr int; n int := 0; k int; r record;
begin
  select * into pol from autopilot_policy where id = 1;
  if not found or not pol.enabled then return 0; end if;
  v_today := (now() at time zone v_tz)::date;
  v_hr := extract(hour from (now() at time zone v_tz))::int;

  if pol.book_on then
    for r in select a.id, coalesce(a.ticket_code, a.id::text) tk, c.name cn, a.starts_at
               from appointments a left join customers c on c.id = a.customer_id
              where a.status = 'upcoming' and a.day = v_today and a.arrived_at is null and a.present_at is null
                and a.starts_at < now() - make_interval(mins => pol.book_late_min)
              order by a.starts_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('book', 'late_booking', r.id::text || ':' || v_today, 'حجز متأخر عن ميعاده: ' || coalesce(r.cn, 'عميل') || ' (' || r.tk || ')',
                'الميعاد كان ' || to_char(r.starts_at at time zone v_tz, 'HH24:MI') || ' والعميل لسه ماوصلش. اتصل بيه أو حرّر الميعاد.', 'queue')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.members_on then
    for r in select m.id, c.name cn, m.plan_name, m.expires_on
               from member_accounts m left join customers c on c.id = m.customer_id
              where m.status = 'active' and m.expires_on between v_today and v_today + pol.mem_expiry_days
              order by m.expires_on limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('members', 'member_expiring', r.id::text || ':' || r.expires_on, 'اشتراك قرّب يخلص: ' || coalesce(r.cn, 'عضو'),
                coalesce(r.plan_name, 'اشتراك') || ' بينتهي ' || r.expires_on || '. كلّمه للتجديد.', 'members')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
    for r in select pr.id, c.name cn, p.name pn, pr.qty, pr.status
               from product_reserves pr left join customers c on c.id = pr.customer_id left join products p on p.id = pr.product_id
              where pr.status in ('pending', 'ready') and pr.created_at < now() - make_interval(days => pol.reserve_days)
              order by pr.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('members', 'reserve_old', r.id::text || ':' || v_today, 'حجز منتج قديم: ' || coalesce(r.pn, 'منتج') || ' × ' || r.qty,
                coalesce(r.cn, 'عميل') || ' · الحالة ' || case r.status when 'ready' then 'جاهز للاستلام' else 'مستني' end || '. جهّزه أو كلّم العميل أو ألغيه.', 'members')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.stock_on then
    for r in select m.id, m.name, m.stock, m.min_stock, m.unit from materials m
              where coalesce(m.active, true) and not coalesce(m.archived, false) and m.min_stock > 0 and m.stock <= m.min_stock
              order by m.stock - m.min_stock limit 30 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('stock', 'low_stock', r.id::text || ':' || v_today, 'خامة قاربت تخلص: ' || r.name,
                'الرصيد ' || r.stock || ' ' || coalesce(r.unit, '') || ' والحد الأدنى ' || r.min_stock || '. اطلبها من المورد.', 'materials')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.cash_on then
    if v_hr >= pol.cash_close_hour and exists (select 1 from invoices i where (i.created_at at time zone v_tz)::date = v_today)
       and not is_day_closed(v_today) then
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cash', 'day_not_closed', v_today::text, 'اليوم لسه ماتقفلش', 'فيه فواتير النهارده والخزنة مش مقفولة. اعمل قفل اليوم.', 'money')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end if;
    for r in select cc.id, cc.day, cc.diff_cash from cash_closings cc
              where cc.day >= v_today - 2 and abs(coalesce(cc.diff_cash, 0)) > pol.cash_diff_limit loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cash', 'cash_diff', r.id::text, 'فرق في الدُرج يوم ' || r.day,
                'الفرق ' || r.diff_cash || ' جنيه وده أكبر من الحد (' || pol.cash_diff_limit || '). راجع حركات اليوم.', 'money')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.team_on then
    for r in select a.id, p.full_name nm, a.check_in from attendance a left join profiles p on p.id = a.staff_id
              where a.check_out is null and a.check_in < now() - make_interval(hours => pol.team_open_hours) order by a.check_in limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('team', 'open_attendance', r.id::text, 'حضور مفتوح من أكتر من ' || pol.team_open_hours || ' ساعة: ' || coalesce(r.nm, 'موظف'),
                'دخل ' || to_char(r.check_in at time zone v_tz, 'DD/MM HH24:MI') || ' ومسجّلش انصراف. صحّح الحضور.', 'att')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
    for r in select l.id, p.full_name nm, l.title from staff_ch_log l left join profiles p on p.id = l.staff_id
              where l.status = 'claimed' and l.created_at < now() - interval '1 day' order by l.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('team', 'challenge_claim', r.id::text, 'تحدي مستني تأكيد: ' || coalesce(r.nm, 'موظف'), r.title || ' · مستني من أكتر من يوم. أكّده أو ارفضه.', 'chw')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
    for r in select x.id, p.full_name nm, x.label from staff_redeems x left join profiles p on p.id = x.staff_id
              where x.status = 'pending' and x.created_at < now() - interval '1 day' order by x.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('team', 'staff_redeem', r.id::text, 'طلب استبدال نقاط مستني: ' || coalesce(r.nm, 'موظف'), r.label || ' · مستني من أكتر من يوم.', 'chw')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.cust_on then
    for r in select q.id, c.name cn from redeem_requests q left join customers c on c.id = q.customer_id
              where q.status = 'pending' and q.created_at < now() - interval '1 day' order by q.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cust', 'redeem_pending', r.id::text, 'طلب استبدال نقاط عميل مستني: ' || coalesce(r.cn, 'عميل'), 'مستني من أكتر من يوم. وافق أو ارفض.', 'cust')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
    for r in select pc.id, c.name cn, pc.amount from pay_claims pc left join customers c on c.id = pc.customer_id
              where pc.status = 'pending' and pc.created_at < now() - interval '2 hours' order by pc.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cust', 'pay_claim', r.id::text, 'عميل قال إنه دفع: ' || coalesce(r.cn, 'عميل'), 'المبلغ ' || r.amount || ' جنيه ومحدش راجعه. اتأكد من التحويل.', 'cust')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.debt_on then
    for r in select i.id, i.no, coalesce(i.debtor_name, c.name) dn, i.unpaid from invoices i left join customers c on c.id = i.customer_id
              where i.unpaid > 0 and i.created_at < now() - make_interval(days => pol.debt_days)
                and not exists (select 1 from invoices s where s.settles_invoice = i.id)
              order by i.created_at limit 20 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('debt', 'old_debt', r.id::text || ':' || v_today, 'دين قديم: ' || coalesce(r.dn, 'عميل') || ' · ' || r.unpaid || ' جنيه',
                'فاتورة ' || r.no || ' ليها أكتر من ' || pol.debt_days || ' يوم من غير سداد. كلّمه.', 'debt')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if pol.cafe_on then
    for r in select cp.id, cp.name, cp.stock, cp.min_stock from cafe_products cp
              where cp.active and cp.track_stock and cp.min_stock > 0 and cp.stock <= cp.min_stock order by cp.stock limit 30 loop
      insert into autopilot_suggestions(area, kind, ref, title, body, tab)
        values ('cafe', 'cafe_low', r.id::text || ':' || v_today, 'منتج كوفي قارب يخلص: ' || r.name, 'الرصيد ' || r.stock || ' والحد الأدنى ' || r.min_stock || '. اشتريه.', 'cafe_prods')
        on conflict (kind, ref) do nothing;
      get diagnostics k = row_count; n := n + k;
    end loop;
  end if;

  if n > 0 then
    begin
      perform push_send(push_staff_ids(array['owner', 'manager'], null, null), 'التشغيل الذاتي: ' || n || ' اقتراح جديد', 'افتح «التشغيل الذاتي» وشوف الاقتراحات.', 'auto', 'ap_scan_' || to_char(now() at time zone v_tz, 'YYYYMMDDHH24'), false);
    exception when others then null;
    end;
  end if;
  return n;
end $$;

create or replace function public.autopilot_suggestion_decide(p_id bigint, p_done boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  update autopilot_suggestions set status = case when p_done then 'done' else 'dismissed' end, decided_by = auth.uid(), decided_at = now()
   where id = p_id and status = 'open';
end $$;

-- قراءة السياسة كاملة + السجل + الاقتراحات المفتوحة
create or replace function public.autopilot_get()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return jsonb_build_object('policy', (select to_jsonb(p) - 'updated_by' from autopilot_policy p where id = 1), 'owner', is_owner(),
    'log', coalesce((select jsonb_agg(to_jsonb(l) order by l.at desc) from (select at, kind, ref, decision, detail from autopilot_log where kind <> 'nudge' order by at desc limit 40) l), '[]'::jsonb),
    'suggestions', coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from (select id, area, kind, title, body, tab, created_at from autopilot_suggestions where status = 'open' order by created_at desc limit 60) s), '[]'::jsonb));
end $$;

create or replace function public.autopilot_save(p_policy jsonb)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_owner() then raise exception 'السياسة للمالك بس'; end if;
  update autopilot_policy set
    enabled = coalesce((p_policy->>'enabled')::boolean, enabled),
    disc_auto = coalesce((p_policy->>'disc_auto')::boolean, disc_auto),
    disc_auto_max_pct = coalesce((p_policy->>'disc_auto_max_pct')::numeric, disc_auto_max_pct),
    disc_auto_daily_total = coalesce((p_policy->>'disc_auto_daily_total')::numeric, disc_auto_daily_total),
    void_auto = coalesce((p_policy->>'void_auto')::boolean, void_auto),
    void_auto_minutes = coalesce((p_policy->>'void_auto_minutes')::int, void_auto_minutes),
    void_auto_max_total = coalesce((p_policy->>'void_auto_max_total')::numeric, void_auto_max_total),
    void_auto_daily_max = coalesce((p_policy->>'void_auto_daily_max')::int, void_auto_daily_max),
    book_on = coalesce((p_policy->>'book_on')::boolean, book_on),
    book_late_min = coalesce((p_policy->>'book_late_min')::int, book_late_min),
    members_on = coalesce((p_policy->>'members_on')::boolean, members_on),
    mem_expiry_days = coalesce((p_policy->>'mem_expiry_days')::int, mem_expiry_days),
    reserve_days = coalesce((p_policy->>'reserve_days')::int, reserve_days),
    stock_on = coalesce((p_policy->>'stock_on')::boolean, stock_on),
    cash_on = coalesce((p_policy->>'cash_on')::boolean, cash_on),
    cash_close_hour = coalesce((p_policy->>'cash_close_hour')::int, cash_close_hour),
    cash_diff_limit = coalesce((p_policy->>'cash_diff_limit')::numeric, cash_diff_limit),
    team_on = coalesce((p_policy->>'team_on')::boolean, team_on),
    team_open_hours = coalesce((p_policy->>'team_open_hours')::int, team_open_hours),
    cust_on = coalesce((p_policy->>'cust_on')::boolean, cust_on),
    debt_on = coalesce((p_policy->>'debt_on')::boolean, debt_on),
    debt_days = coalesce((p_policy->>'debt_days')::int, debt_days),
    cafe_on = coalesce((p_policy->>'cafe_on')::boolean, cafe_on),
    updated_by = auth.uid(), updated_at = now()
   where id = 1;
  insert into autopilot_log(kind, ref, decision, detail) values ('policy', null, 'changed', p_policy);
end $$;

do $$
declare f text;
begin
  foreach f in array array['autopilot_get()', 'autopilot_save(jsonb)', 'autopilot_suggestion_decide(bigint,boolean)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
  revoke all on function public.autopilot_scan() from public, anon, authenticated;
  grant execute on function public.autopilot_scan() to service_role;
  if exists (select 1 from cron.job where jobname = 'autopilot-scan') then perform cron.unschedule('autopilot-scan'); end if;
  perform cron.schedule('autopilot-scan', '*/15 * * * *', 'select public.autopilot_scan()');
end $$;

notify pgrst, 'reload schema';
