-- تقرير الحجوزات والدور: اللي حضر واللي ماجاش، متوسط وقت الانتظار ومدة الخدمة، أوقات الزحمة، وأداء كل حلاق.
-- قراءة فقط من حجوزات الصالون الفعلية. الانتظار = من وصول العميل لبداية الخدمة. آمن لو اتشغّل أكتر من مرة.
create or replace function public.booking_report(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_days int := least(greatest(coalesce(p_days, 30), 7), 365); v_from timestamptz := now() - make_interval(days => v_days); v_tz text := my_tz(); v_res jsonb;
begin
  if not (is_mgr() or has_perm('view_reports')) then raise exception 'غير مصرح'; end if;
  with a as (
    select x.*, coalesce(x.arrived_at, x.present_at) arr,
           extract(epoch from (x.service_started_at - coalesce(x.arrived_at, x.present_at))) / 60 wait_min,
           extract(epoch from (coalesce(x.completed_at, x.finished_at) - x.service_started_at)) / 60 svc_min
      from appointments x where x.created_at >= v_from)
  select jsonb_build_object(
    'days', v_days,
    'status', coalesce((select jsonb_object_agg(s, n) from (select status::text s, count(*) n from a group by 1) q), '{}'::jsonb),
    'no_show_rate', (select round(100.0 * count(*) filter (where status::text = 'no_show') / nullif(count(*) filter (where status::text in ('done', 'no_show')), 0), 1) from a),
    'wait', jsonb_build_object('avg', (select round(avg(wait_min)::numeric, 1) from a where status::text = 'done' and wait_min > 0 and wait_min < 300),
        'n', (select count(*) from a where status::text = 'done' and wait_min > 0 and wait_min < 300),
        'over30', (select count(*) from a where status::text = 'done' and wait_min >= 30 and wait_min < 300)),
    'service_min', (select round(avg(svc_min)::numeric, 1) from a where status::text = 'done' and svc_min > 0 and svc_min < 300),
    'by_hour', coalesce((select jsonb_object_agg(h, n) from (select extract(hour from arr at time zone v_tz)::int h, count(*) n from a where arr is not null and status::text = 'done' group by 1) q), '{}'::jsonb),
    'by_weekday', coalesce((select jsonb_object_agg(d, n) from (select extract(dow from arr at time zone v_tz)::int d, count(*) n from a where arr is not null and status::text = 'done' group by 1) q), '{}'::jsonb),
    'barbers', coalesce((select jsonb_agg(jsonb_build_object('name', p.full_name, 'done', q.done, 'no_show', q.ns, 'wait', q.w, 'svc', q.sv) order by q.done desc)
        from (select barber_id, count(*) filter (where status::text = 'done') done, count(*) filter (where status::text = 'no_show') ns,
                     round((avg(wait_min) filter (where status::text = 'done' and wait_min > 0 and wait_min < 300))::numeric, 1) w,
                     round((avg(svc_min) filter (where status::text = 'done' and svc_min > 0 and svc_min < 300))::numeric, 1) sv
                from a where barber_id is not null group by 1) q join profiles p on p.id = q.barber_id), '[]'::jsonb)
  ) into v_res;
  return v_res;
end $$;
revoke all on function public.booking_report(int) from public, anon;
grant execute on function public.booking_report(int) to authenticated, service_role;
notify pgrst, 'reload schema';
