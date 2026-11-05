-- رقم موبايل عميل كل تذكرة في طابور الحلاق (لزرار واتساب في شاشة الصنايعي).
-- نفس شروط الرؤية بتاعة my_queue بالظبط؛ بيرجّع id + الرقم بس.
create or replace function public.my_queue_phones(p_barber uuid default null, p_day date default null)
returns table(id bigint, phone text)
language sql stable security definer set search_path = public as $$
  select a.id, c.phone::text
    from appointments a left join customers c on c.id = a.customer_id
   where a.day = coalesce(p_day, (now() at time zone my_tz())::date)
     and a.status::text in ('upcoming', 'checked_in', 'in_service')
     and ((coalesce(p_barber, auth.uid()) = auth.uid() and has_perm('view_own_schedule') and a.barber_id = auth.uid())
          or ((is_mgr() or has_perm('manage_appts')) and (p_barber is null or a.barber_id = p_barber)))
$$;
revoke all on function public.my_queue_phones(uuid, date) from public, anon;
grant execute on function public.my_queue_phones(uuid, date) to authenticated;
-- للتراجع: drop function public.my_queue_phones(uuid, date);
