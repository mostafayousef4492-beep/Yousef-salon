-- المبلغ المدفوع الفعلي: لو العميل دفع أكتر من الحساب، الزيادة بتتسجل على الفاتورة
-- (إجمالي الفاتورة بيفضل سعر الخدمة، فالعمولات والمبيعات ماتتأثرش) وبتدخل في حساب الدرج/الكارت/المحفظة.
alter table public.invoices add column if not exists extra_paid numeric(10,2) not null default 0;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_extra_paid_check') then
    alter table public.invoices add constraint invoices_extra_paid_check check (extra_paid >= 0);
  end if;
end $$;

create or replace function public.invoice_set_paid(p_invoice bigint, p_paid numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i invoices;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if not is_mgr() and (i.created_at < now() - interval '15 minutes' or i.cashier_id is distinct from auth.uid()) then
    raise exception 'تعديل المبلغ المدفوع للمدير بعد ما الفاتورة تعدي 15 دقيقة'; end if;
  if p_paid is null or p_paid < i.total then raise exception 'المبلغ المدفوع (%) أقل من المطلوب (%)', coalesce(p_paid,0), i.total; end if;
  if p_paid - i.total > 100000 then raise exception 'المبلغ كبير بشكل غير طبيعي'; end if;
  update invoices set extra_paid = p_paid - i.total where id = p_invoice;
  return jsonb_build_object('total', i.total, 'paid', p_paid, 'extra', p_paid - i.total);
end $$;
revoke all on function public.invoice_set_paid(bigint,numeric) from public, anon;
grant execute on function public.invoice_set_paid(bigint,numeric) to authenticated;

create or replace function public.range_figures(p_from date, p_to date)
 returns jsonb language plpgsql stable set search_path to 'public' as $$
declare v_tz text := my_tz(); r jsonb;
begin
  select jsonb_build_object(
    'invoices', (select count(*) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to),
    'revenue', (select coalesce(sum(i.total),0) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to),
    'tips', (select coalesce(sum(i.extra_paid),0) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to),
    'cash_sales', (select coalesce(sum(i.total + i.extra_paid),0) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to and i.payment_method = 'cash'),
    'card_sales', (select coalesce(sum(i.total + i.extra_paid),0) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to and i.payment_method = 'card'),
    'wallet_sales', (select coalesce(sum(i.total + i.extra_paid),0) from invoices i where (i.created_at at time zone v_tz)::date between p_from and p_to and i.payment_method = 'wallet'),
    'exp_cash', (select coalesce(sum(e.amount),0) from expenses e where e.spent_on between p_from and p_to and e.paid_from = 'drawer' and e.purchase_id is null),
    'pur_cash', (select coalesce(sum(p.paid),0) from purchases p where p.bought_on between p_from and p_to and p.paid_from = 'drawer'),
    'sup_cash', (select coalesce(sum(s.amount),0) from supplier_payments s where s.paid_on between p_from and p_to and s.paid_from = 'drawer'),
    'sal_cash', (select coalesce(sum(s.amount),0) from salary_payments s where s.paid_on between p_from and p_to and s.paid_from = 'drawer'),
    'adv_cash', (select coalesce(sum(t.amount),0) from staff_transactions t where t.kind = 'advance' and (t.created_at at time zone v_tz)::date between p_from and p_to),
    'moves_out', (select coalesce(sum(m.amount),0) from cash_moves m where m.day between p_from and p_to and m.kind = 'withdraw'),
    'moves_in', (select coalesce(sum(m.amount),0) from cash_moves m where m.day between p_from and p_to and m.kind = 'deposit'),
    'opening', coalesce((select c.counted_cash from cash_closings c where c.day < p_from order by c.day desc limit 1), 0)
  ) into r;
  return r;
end $$;
