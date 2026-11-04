-- سحب من الدرج "من فلوس أيام فاتت": بيفضل محسوب في الموجود في الدرج (day_figures / التقارير)
-- لكن الرئيسية بتخصمه من "حركة اليوم". علامة بس على الصف، مفيش تغيير في أي دالة.
begin;
alter table public.cash_moves add column if not exists prev_day boolean not null default false;
commit;
