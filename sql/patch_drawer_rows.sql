-- ============================================================================
-- patch_drawer_rows.sql — تفاصيل الدرج بنفس منطق range_figures بالظبط
--   drawer_rows(p_from,p_to,p_kind): حركات كل بند (sales,in,out,exp,adv,sal,pur,sup) بنفس حساب "يوم العمل"
--                                    ومعاها الكافيه، علشان مجموع التفاصيل = الرقم اللي في الكارت بالظبط.
--   drawer_audit(p_limit):          الأيام اللي اتقفلت وبعد كده حركاتها اتغيّرت (إضافة/تعديل/حذف بعد القفل).
-- آمنة: دوال قراءة بس (مفيش تعديل في أي بيانات)، ومتاحة للمدير/المالك زي drawer_range.
-- ============================================================================

create or replace function public.drawer_rows(p_from date, p_to date, p_kind text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare v_tz text := my_tz(); r jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'الفترة غير صحيحة'; end if;
  if p_kind not in ('sales','in','out','exp','adv','sal','pur','sup') then raise exception 'نوع غير معروف'; end if;
  with w as (select b.day, p24b_start(b.day) s, coalesce(b.closed_at, 'infinity'::timestamptz) e from business_days b),
  a as (
    select 'sales'::text k, ('فاتورة #' || i.no::text) lbl, null::text sub,
           coalesce((select w.day from w where i.created_at >= w.s and i.created_at < w.e order by w.day desc limit 1), (i.created_at at time zone v_tz)::date) d,
           i.created_at at_, i.total amt
      from invoices i where i.payment_method = 'cash'
    union all
    select 'sales', ('كافيه #' || s.id::text), 'مبيعات كافيه',
           coalesce((select w.day from w where s.created_at >= w.s and s.created_at < w.e order by w.day desc limit 1), (s.created_at at time zone v_tz)::date),
           s.created_at, s.total
      from cafe_sales s where s.status = 'paid' and s.payment_method = 'cash'
    union all
    select 'in', coalesce(nullif(m.note,''), 'إيداع في الدرج'), null, m.day, m.created_at, m.amount from cash_moves m where m.kind = 'deposit'
    union all
    select 'out', coalesce(nullif(m.note,''), 'سحب من الدرج'), null, m.day, m.created_at, m.amount from cash_moves m where m.kind = 'withdraw'
    union all
    select 'exp', e.category || coalesce(' — ' || nullif(e.note,''), ''), null, e.spent_on, e.created_at, e.amount
      from expenses e where e.paid_from = 'drawer' and e.purchase_id is null
    union all
    select 'exp', 'كافيه · ' || e.category || coalesce(' — ' || nullif(e.note,''), ''), null, e.spent_on, e.created_at, e.amount
      from cafe_expenses e where e.paid_from = 'drawer' and e.purchase_id is null
    union all
    select 'adv', coalesce(p.full_name, 'موظف') || coalesce(' — ' || nullif(t.note,''), ''), null,
           coalesce((select w.day from w where t.created_at >= w.s and t.created_at < w.e order by w.day desc limit 1), (t.created_at at time zone v_tz)::date),
           t.created_at, t.amount
      from staff_transactions t left join profiles p on p.id = t.staff_id where t.kind = 'advance'
    union all
    select 'sal', coalesce(p.full_name, 'موظف') || coalesce(' — ' || nullif(s.note,''), ''), null, s.paid_on, s.created_at, s.amount
      from salary_payments s left join profiles p on p.id = s.staff_id where s.paid_from = 'drawer'
    union all
    select 'pur', 'مشتريات' || coalesce(' — ' || nullif(p.note,''), ''), null, p.bought_on, p.created_at, p.paid
      from purchases p where p.paid_from = 'drawer'
    union all
    select 'pur', 'مشتريات كافيه' || coalesce(' — ' || nullif(p.note,''), ''), null, p.bought_on, p.created_at, p.total
      from cafe_purchases p where p.paid_from = 'drawer'
    union all
    select 'sup', coalesce(su.name, 'مورد') || coalesce(' — ' || nullif(s.note,''), ''), null, s.paid_on, s.created_at, s.amount
      from supplier_payments s left join suppliers su on su.id = s.supplier_id where s.paid_from = 'drawer'
  )
  select coalesce(jsonb_agg(jsonb_build_object('label', lbl, 'sub', sub, 'day', d, 'amount', amt) order by d desc, at_ desc nulls last), '[]'::jsonb)
    into r from a where k = p_kind and d between p_from and p_to;
  return r;
end $fn$;

create or replace function public.drawer_audit(p_limit int default 30)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $fn$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((
    select jsonb_agg(t.x order by t.x->>'day' desc)
    from (
      select jsonb_build_object('day', c.day, 'at_close', round(c.expected_cash - c.opening, 2), 'now_net', n.v, 'changed', round(n.v - (c.expected_cash - c.opening), 2)) x
      from (select * from cash_closings order by day desc limit greatest(1, least(coalesce(p_limit, 30), 120))) c
      cross join lateral (select round(expected_cash_of(range_figures(c.day, c.day), 0), 2) v) n
      where abs(n.v - (c.expected_cash - c.opening)) >= 1
    ) t
  ), '[]'::jsonb);
end $fn$;

revoke all on function public.drawer_rows(date, date, text) from public, anon;
revoke all on function public.drawer_audit(int) from public, anon;
grant execute on function public.drawer_rows(date, date, text) to authenticated;
grant execute on function public.drawer_audit(int) to authenticated;
