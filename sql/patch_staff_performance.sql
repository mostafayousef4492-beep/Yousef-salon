-- ============================================================================
-- patch_staff_performance.sql — أداء كل حلاق في فترة (قراءة بس، للمالك/المدير)
--   عدد الفواتير والعملاء (المسجّلين)، الإيراد المحصّل، إجمالي الخصومات ونسبتها، متوسط الفاتورة، العمولة التقديرية.
--   العمولة = (إجمالي الفاتورة − حصة المساعد − الخامات الاختيارية) × نسبة الحلاق (أو نسبة الفاتورة الخاصة). تقديري ومبتغيّرش أي بيانات.
-- ============================================================================
create or replace function public.staff_performance(p_from date, p_to date)
returns jsonb
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare v_tz text := my_tz(); v_from timestamptz; v_to timestamptz; r jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'الفترة غير صحيحة'; end if;
  v_from := (p_from::timestamp) at time zone v_tz;
  v_to   := ((p_to + 1)::timestamp) at time zone v_tz;
  with inv as (
    select i.id, i.barber_id, i.customer_id, i.subtotal, coalesce(i.discount, 0) as discount, i.total,
           coalesce((select sum(ii.assistant_cut) from invoice_items ii where ii.invoice_id = i.id), 0) as acut,
           coalesce((select sum(ii.mat_cost) from invoice_items ii where ii.invoice_id = i.id), 0) as mc,
           coalesce(ic.pct, pr.commission_pct, 0) as pct
      from invoices i
      left join invoice_commissions ic on ic.invoice_id = i.id
      left join profiles pr on pr.id = i.barber_id
     where i.created_at >= v_from and i.created_at < v_to and i.barber_id is not null
  ), per as (
    select barber_id, count(*) as invoices, count(distinct customer_id) as customers,
           sum(total) as collected, sum(subtotal) as gross, sum(discount) as discounts,
           sum(greatest(total - acut - mc, 0) * pct / 100) as commission
      from inv group by barber_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'staff_id', per.barber_id, 'name', coalesce(p.full_name, 'محذوف'), 'invoices', per.invoices, 'customers', per.customers,
           'collected', round(per.collected, 2), 'gross', round(per.gross, 2), 'discounts', round(per.discounts, 2),
           'discount_pct', case when per.gross > 0 then round(per.discounts / per.gross * 100, 1) else 0 end,
           'avg_invoice', case when per.invoices > 0 then round(per.collected / per.invoices, 2) else 0 end,
           'commission', round(per.commission, 2)) order by per.collected desc), '[]'::jsonb)
    into r from per left join profiles p on p.id = per.barber_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'rows', r);
end $fn$;
revoke all on function public.staff_performance(date, date) from public, anon;
grant execute on function public.staff_performance(date, date) to authenticated;
