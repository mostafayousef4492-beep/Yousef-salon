-- صرف راتب جزء منه من فلوس أيام فاتت: بيتسجل في salary_payments.prev_amount.
-- حركة اليوم في الرئيسية مبتحسبش الجزء ده (زي سحب/سلف «من أيام فاتت»)، لكن التقارير والدرج الفعلي بيحسبوا المبلغ كله.
-- آمن للتكرار. مفيش بيانات بتتمسح.
alter table public.salary_payments add column if not exists prev_amount numeric not null default 0 check (prev_amount >= 0 and prev_amount <= amount);

create or replace function public.day_prev_out(p_day date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s timestamptz; e timestamptz; m numeric; a numeric; sl numeric;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  s := coalesce(p24b_start(p_day), p_day::timestamptz);
  select coalesce(closed_at, now()) into e from business_days where day = p_day;
  if e is null then e := now(); end if;
  select coalesce(sum(amount),0) into m from cash_moves where day = p_day and kind = 'withdraw' and prev_day;
  select coalesce(sum(amount),0) into a from staff_transactions where kind = 'advance' and prev_day and created_at >= s and created_at <= e;
  select coalesce(sum(prev_amount),0) into sl from salary_payments where paid_on = p_day and paid_from = 'drawer';
  return jsonb_build_object('moves', m, 'adv', a, 'sal', sl);
end $$;

-- تصحيح صرف راتب عبد الرحمن محمد (2,416 يوم 10/11): 1,000 منهم من فلوس أيام فاتت
update public.salary_payments sp set prev_amount = 1000
from public.profiles pr
where pr.id = sp.staff_id and pr.full_name like '%عبد الرحمن%' and sp.amount = 2416 and sp.paid_on = '2026-11-10' and sp.paid_from = 'drawer';
