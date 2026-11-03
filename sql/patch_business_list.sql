-- قائمة أيام العمل (للتقارير: تجميع الفواتير على يوم العمل مش على التاريخ). آمن للتكرار.
create or replace function public.business_days_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when is_mgr() or has_perm('use_pos') then
    coalesce((select jsonb_agg(jsonb_build_object('day', b.day, 'opened_at', b.opened_at, 'closed_at', b.closed_at) order by b.day)
              from business_days b where b.day >= current_date - 400), '[]'::jsonb)
  else '[]'::jsonb end
$$;
revoke all on function public.business_days_list() from public, anon;
grant execute on function public.business_days_list() to authenticated;
