-- تعديل المبلغ المدفوع لفاتورة في يوم مقفول: لازم تأكيد صريح (p_force)، وقفلة اليوم بتتحدّث تلقائياً بعد التعديل
-- (المتوقع بيتحسب من جديد والمعدود يفضل زي ما هو، والقفلة القديمة بتتسجّل في deletion_log).
-- بيستبدل invoice_set_paid(bigint, numeric) بنسخة فيها p_force. آمن للتشغيل أكتر من مرة.
drop function if exists public.invoice_set_paid(bigint, numeric);
create or replace function public.invoice_set_paid(p_invoice bigint, p_paid numeric, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i invoices; v_day date; v_closed boolean := false;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if not is_mgr() and (i.created_at < now() - interval '15 minutes' or i.cashier_id is distinct from auth.uid()) then
    raise exception 'تعديل المبلغ المدفوع للمدير بعد ما الفاتورة تعدي 15 دقيقة'; end if;
  if p_paid is null or p_paid < i.subtotal - i.discount then raise exception 'المبلغ المدفوع (%) أقل من المطلوب (%)', coalesce(p_paid,0), i.subtotal - i.discount; end if;
  if p_paid - (i.subtotal - i.discount) > 100000 then raise exception 'المبلغ كبير بشكل غير طبيعي'; end if;
  -- يوم الفاتورة = أول يوم اتقفل بعد وقتها (نفس تعريف نافذة اليوم)
  select b.day into v_day from business_days b where b.closed_at is not null and i.created_at < b.closed_at order by b.closed_at limit 1;
  v_closed := v_day is not null and exists (select 1 from cash_closings c where c.day = v_day);
  if v_closed then
    if not is_mgr() then raise exception 'اليوم ده مقفول: التعديل للمدير'; end if;
    if not coalesce(p_force, false) then
      return jsonb_build_object('needs_force', true, 'day', v_day, 'due', i.subtotal - i.discount);
    end if;
  end if;
  update invoices set total = p_paid, extra_paid = p_paid - (i.subtotal - i.discount) where id = p_invoice;
  if v_closed then perform p32_refresh_closing(v_day, 'invoice_set_paid #' || i.no); end if;
  return jsonb_build_object('due', i.subtotal - i.discount, 'paid', p_paid, 'extra', p_paid - (i.subtotal - i.discount), 'refreshed_day', case when v_closed then v_day end);
end $$;
revoke all on function public.invoice_set_paid(bigint, numeric, boolean) from public, anon;
grant execute on function public.invoice_set_paid(bigint, numeric, boolean) to authenticated;
