-- المبلغ المدفوع الفعلي: لو العميل دفع أكتر من الحساب، إجمالي الفاتورة (total) بيبقى المبلغ الفعلي،
-- فالعمولة والمبيعات والدرج والتقارير كلها بتتحسب عليه. extra_paid = الزيادة عن (المجموع - الخصم).
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
  if p_paid is null or p_paid < i.subtotal - i.discount then raise exception 'المبلغ المدفوع (%) أقل من المطلوب (%)', coalesce(p_paid,0), i.subtotal - i.discount; end if;
  if p_paid - (i.subtotal - i.discount) > 100000 then raise exception 'المبلغ كبير بشكل غير طبيعي'; end if;
  update invoices set total = p_paid, extra_paid = p_paid - (i.subtotal - i.discount) where id = p_invoice;
  return jsonb_build_object('due', i.subtotal - i.discount, 'paid', p_paid, 'extra', p_paid - (i.subtotal - i.discount));
end $$;
revoke all on function public.invoice_set_paid(bigint,numeric) from public, anon;
grant execute on function public.invoice_set_paid(bigint,numeric) to authenticated;
