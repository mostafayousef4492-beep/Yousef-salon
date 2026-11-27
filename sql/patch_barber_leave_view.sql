-- إظهار الصنايعي اللي في إجازة (أو يوم راحته) في صفحة الحجز كـ«في إجازة» بدل ما يختفي.
-- الإجازة بتتسجل من: الفريق ← الحضور/الشيفت ← الصنايعي ← «إجازة محددة» (من/إلى/السبب).
-- بيرجّع اسم الصنايعي ونوع الغياب وتاريخ الرجوع بس. آمن لو اتشغّل أكتر من مرة.
create or replace function public.barbers_on_leave(p_day date)
returns table(id uuid, full_name text, kind text, back_on date)
language sql stable security definer set search_path = public, pg_temp as $$
  select p.id, p.full_name,
         case when exists (select 1 from staff_leaves l where l.staff_id = p.id and p_day between l.from_date and l.to_date) then 'leave' else 'off' end,
         (select max(l.to_date) + 1 from staff_leaves l where l.staff_id = p.id and p_day between l.from_date and l.to_date)
    from barber_hours(p_day) b join profiles p on p.id = b.barber_id
   where b.is_off
   order by p.full_name
$$;
revoke all on function public.barbers_on_leave(date) from public;
grant execute on function public.barbers_on_leave(date) to anon, authenticated;
notify pgrst, 'reload schema';
