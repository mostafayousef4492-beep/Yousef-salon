-- تقرير اليوم (بداية / منتصف / إغلاق) + تنبيهات ذكية من أرقام اليوم الحقيقية. قراءة فقط: مبيغيّرش أي بيانات.
-- بيستخدم day_figures الأصلية لأرقام الخزنة، وبيضيف عليها فحوصات (إلغاءات، خصومات، حضور، مخزون، فواتير واقفة...).
-- ملخص آخر اليوم بيتبعت للمالك إشعار مرة واحدة يوميًا (الساعة 11 بالليل بتوقيت الصالون تقريبًا).
-- آمن لو اتشغّل أكتر من مرة. لو حبيت توقف الإشعار اليومي: select cron.unschedule('day-report-push');

create table if not exists public.day_report_runs (
  day date primary key,
  sent_at timestamptz not null default now()
);
alter table public.day_report_runs enable row level security;
revoke all on public.day_report_runs from public, anon, authenticated;

-- النواة (من غير فحص صلاحيات — للاستخدام الداخلي والجدولة فقط)
create or replace function public.day_report_core(p_day date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_tz text := my_tz(); v_fig jsonb; v_inv record; v_void int; v_voidsum numeric;
  v_exp numeric; v_att int; v_late int; v_lateMin int; v_absent jsonb; v_stale int; v_lowM jsonb; v_lowP jsonb;
  v_apr int; v_closed boolean; v_cl cash_closings; v_alerts jsonb := '[]'::jsonb; v_pct numeric;
  v_now timestamp := now() at time zone my_tz(); v_today boolean := (now() at time zone my_tz())::date = p_day;
begin
  v_fig := day_figures(p_day);
  select count(*) n, coalesce(sum(total), 0) total, coalesce(sum(subtotal), 0) subtotal, coalesce(sum(discount), 0) disc,
         coalesce(sum(company_discount), 0) cdisc, coalesce(sum(unpaid), 0) unpaid, count(*) filter (where unpaid > 0) unpaid_n
    into v_inv from invoices where p24b_in_day(created_at, p_day, v_tz);
  select count(*), coalesce(sum(nullif(row_data->>'total', '')::numeric), 0) into v_void, v_voidsum
    from deletion_log where table_name = 'invoices' and p24b_in_day(deleted_at, p_day, v_tz);
  select coalesce(sum(amount), 0) into v_exp from expenses where spent_on = p_day;
  select count(distinct staff_id), count(*) filter (where late_min > 0), coalesce(sum(late_min), 0)
    into v_att, v_late, v_lateMin from attendance where (check_in at time zone v_tz)::date = p_day;
  v_absent := '[]'::jsonb;
  if v_today then
    select coalesce(jsonb_agg(p.full_name order by p.full_name), '[]'::jsonb) into v_absent
      from staff_shifts s join profiles p on p.id = s.staff_id
     where s.weekday = extract(dow from p_day)::int and not s.is_off and s.start_time < v_now::time - interval '60 minutes'
       and p.role::text not in ('owner', 'customer')
       and not exists (select 1 from attendance a where a.staff_id = s.staff_id and (a.check_in at time zone v_tz)::date = p_day)
       and not exists (select 1 from staff_leaves l where l.staff_id = s.staff_id and p_day between l.from_date and l.to_date);
  end if;
  select count(*) into v_stale from open_invoices where opened_at < now() - interval '3 hours';
  select coalesce(jsonb_agg(name order by name), '[]'::jsonb) into v_lowM from (select name from materials where active and min_stock > 0 and stock <= min_stock limit 8) x;
  select coalesce(jsonb_agg(name order by name), '[]'::jsonb) into v_lowP from (select name from products where active and min_stock > 0 and stock <= min_stock limit 8) x;
  select (select count(*) from discount_requests where status = 'pending') + (select count(*) from approval_requests where status = 'pending') into v_apr;
  select * into v_cl from cash_closings where day = p_day order by id desc limit 1;
  v_closed := v_cl.id is not null;
  v_pct := case when v_inv.subtotal > 0 then round(v_inv.disc / v_inv.subtotal * 100, 1) else 0 end;

  -- التنبيهات (كل واحد ليه سبب واضح من الأرقام)
  if v_void >= 1 then v_alerts := v_alerts || jsonb_build_object('level', case when v_void >= 3 then 'high' else 'warn' end, 'text', v_void || ' فاتورة اتلغت النهارده بإجمالي ' || v_voidsum || ' ج'); end if;
  if v_pct >= 15 then v_alerts := v_alerts || jsonb_build_object('level', 'warn', 'text', 'نسبة الخصومات ' || v_pct || '% من المبيعات (قبل الخصم)'); end if;
  if v_inv.unpaid_n > 0 then v_alerts := v_alerts || jsonb_build_object('level', 'info', 'text', v_inv.unpaid_n || ' فاتورة فيها مبلغ آجل بإجمالي ' || v_inv.unpaid || ' ج'); end if;
  if v_stale > 0 then v_alerts := v_alerts || jsonb_build_object('level', 'warn', 'text', v_stale || ' فاتورة مفتوحة من أكتر من 3 ساعات'); end if;
  if jsonb_array_length(v_absent) > 0 then v_alerts := v_alerts || jsonb_build_object('level', 'warn', 'text', 'لسه ماسجلوش حضور: ' || (select string_agg(x, '، ') from jsonb_array_elements_text(v_absent) x)); end if;
  if jsonb_array_length(v_lowM) + jsonb_array_length(v_lowP) > 0 then v_alerts := v_alerts || jsonb_build_object('level', 'warn', 'text', 'مخزون وصل للحد الأدنى: ' || (select string_agg(x, '، ') from (select jsonb_array_elements_text(v_lowM) x union all select jsonb_array_elements_text(v_lowP)) q)); end if;
  if v_apr > 0 then v_alerts := v_alerts || jsonb_build_object('level', 'info', 'text', v_apr || ' طلب موافقة مستني قرارك'); end if;
  if v_closed and (coalesce(v_cl.diff_cash, 0) <> 0) then v_alerts := v_alerts || jsonb_build_object('level', 'high', 'text', 'فرق في جرد الكاش: ' || v_cl.diff_cash || ' ج'); end if;
  if v_today and not v_closed and v_now::time >= time '23:30' then v_alerts := v_alerts || jsonb_build_object('level', 'info', 'text', 'اليوم لسه ما اتقفلش في الخزنة'); end if;

  return jsonb_build_object('day', p_day, 'closed', v_closed, 'figures', v_fig,
    'sales', jsonb_build_object('invoices', v_inv.n, 'total', v_inv.total, 'subtotal', v_inv.subtotal, 'discount', v_inv.disc, 'discount_pct', v_pct, 'company_discount', v_inv.cdisc, 'unpaid', v_inv.unpaid),
    'voids', jsonb_build_object('count', v_void, 'total', v_voidsum),
    'expenses', v_exp,
    'attendance', jsonb_build_object('present', v_att, 'late', v_late, 'late_min', v_lateMin, 'absent', v_absent),
    'open_stale', v_stale, 'low_stock', jsonb_build_object('materials', v_lowM, 'products', v_lowP),
    'pending_approvals', v_apr,
    'closing', case when v_closed then jsonb_build_object('diff_cash', v_cl.diff_cash, 'diff_card', v_cl.diff_card, 'diff_wallet', v_cl.diff_wallet) end,
    'alerts', v_alerts);
end $$;
revoke all on function public.day_report_core(date) from public, anon, authenticated;
grant execute on function public.day_report_core(date) to service_role;

-- للمدير والمالك
create or replace function public.day_report(p_day date default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return day_report_core(coalesce(p_day, (now() at time zone my_tz())::date));
end $$;
revoke all on function public.day_report(date) from public, anon;
grant execute on function public.day_report(date) to authenticated, service_role;

-- إشعار آخر اليوم للمالك (مرة واحدة في اليوم)
create or replace function public.day_report_push()
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare v_day date := (now() at time zone my_tz())::date; r jsonb; v_body text; v_n int;
begin
  if (now() at time zone my_tz())::time < time '23:00' then return 0; end if;
  insert into day_report_runs(day) values (v_day) on conflict do nothing;
  if not found then return 0; end if;
  r := day_report_core(v_day);
  v_n := jsonb_array_length(r->'alerts');
  v_body := 'مبيعات ' || (r->'sales'->>'total') || ' ج (' || (r->'sales'->>'invoices') || ' فاتورة) · مصروفات ' || (r->>'expenses') || ' ج'
            || case when v_n > 0 then ' · ' || v_n || ' تنبيه' else ' · مفيش تنبيهات ✓' end;
  begin
    perform push_send(push_staff_ids(array['owner'], null, null), 'ملخص اليوم', v_body, 'day', 'dayrep_' || v_day, false);
  exception when others then null;
  end;
  return 1;
end $$;
revoke all on function public.day_report_push() from public, anon, authenticated;
grant execute on function public.day_report_push() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'day-report-push') then perform cron.unschedule('day-report-push'); end if;
  perform cron.schedule('day-report-push', '10 * * * *', 'select public.day_report_push()');
end $$;

notify pgrst, 'reload schema';
