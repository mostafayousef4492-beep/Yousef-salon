-- الدفع الإلكتروني بدون بوابة: فودافون كاش / إنستا باي بتتسجّل كـ "محفظة" + قناة + رقم العملية (بيتمنع تكراره).
-- مفيش تأكيد أوتوماتيك من البنك/فودافون (ده محتاج بوابة دفع وحساب تاجر)؛ رقم العملية بيخلّي المراجعة مع كشف الحساب سهلة وبيمنع استخدام نفس التحويل على فاتورتين.
-- آمن للتشغيل أكتر من مرة. الإعدادات: vodafone_cash_number / instapay_address (من الإعدادات ← الكاشير).
alter table public.invoices add column if not exists pay_channel text, add column if not exists pay_ref text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_pay_channel_check') then
    alter table public.invoices add constraint invoices_pay_channel_check check (pay_channel is null or pay_channel in ('vodafone_cash','instapay','other_wallet'));
  end if;
end $$;
create unique index if not exists invoices_pay_ref_uq on public.invoices (pay_channel, lower(btrim(pay_ref))) where pay_ref is not null and pay_channel in ('vodafone_cash','instapay');

-- هل رقم العملية ده اتسجّل قبل كده؟ (قبل الدفع، عشان الكاشير يعرف قبل ما يقفل الفاتورة)
create or replace function public.epay_ref_used(p_channel text, p_ref text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not (is_mgr() or can_use_pos()) then null
    else exists (select 1 from invoices where pay_channel = p_channel and lower(btrim(pay_ref)) = lower(btrim(p_ref))) end
$$;
revoke all on function public.epay_ref_used(text, text) from public, anon;
grant execute on function public.epay_ref_used(text, text) to authenticated;

-- تسجيل قناة الدفع ورقم العملية على فاتورة اتدفعت "محفظة". الكاشير على فاتورته خلال 15 دقيقة، والمدير في أي وقت.
create or replace function public.invoice_set_payment(p_invoice bigint, p_channel text, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare i invoices; r text := nullif(btrim(coalesce(p_ref, '')), '');
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if not is_mgr() and (i.created_at < now() - interval '15 minutes' or i.cashier_id is distinct from auth.uid()) then
    raise exception 'تعديل طريقة الدفع للمدير بعد ما الفاتورة تعدي 15 دقيقة'; end if;
  if i.payment_method <> 'wallet' then raise exception 'القناة دي للدفع بالمحفظة بس'; end if;
  if p_channel is null or p_channel not in ('vodafone_cash', 'instapay', 'other_wallet') then raise exception 'قناة دفع غير صحيحة'; end if;
  if p_channel in ('vodafone_cash', 'instapay') and (r is null or char_length(r) < 4) then raise exception 'اكتب رقم العملية (4 أرقام/حروف على الأقل)'; end if;
  begin
    update invoices set pay_channel = p_channel, pay_ref = r where id = p_invoice;
  exception when unique_violation then
    raise exception 'رقم العملية ده اتسجّل قبل كده على فاتورة تانية';
  end;
end $$;
revoke all on function public.invoice_set_payment(bigint, text, text) from public, anon;
grant execute on function public.invoice_set_payment(bigint, text, text) to authenticated;
