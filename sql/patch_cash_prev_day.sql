-- سحب من الدرج / سلفة موظف "من فلوس أيام فاتت":
--  • بيفضل محسوب في الموجود في الدرج (day_figures / التقارير) زي ما هو
--  • الرئيسية بتخصمه من "حركة اليوم" بس (عن طريق day_prev_out)
-- علامة على الصف، مفيش تغيير في أي دالة حسابات موجودة.
begin;
alter table public.cash_moves        add column if not exists prev_day boolean not null default false;
alter table public.staff_transactions add column if not exists prev_day boolean not null default false;

create or replace function public.day_prev_out(p_day date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s timestamptz; e timestamptz; m numeric; a numeric;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  s := coalesce(p24b_start(p_day), p_day::timestamptz);
  select coalesce(closed_at, now()) into e from business_days where day = p_day;
  if e is null then e := now(); end if;
  select coalesce(sum(amount),0) into m from cash_moves where day = p_day and kind = 'withdraw' and prev_day;
  select coalesce(sum(amount),0) into a from staff_transactions where kind = 'advance' and prev_day and created_at >= s and created_at <= e;
  return jsonb_build_object('moves', m, 'adv', a);
end $$;
revoke all on function public.day_prev_out(date) from public;
grant execute on function public.day_prev_out(date) to authenticated;
commit;
