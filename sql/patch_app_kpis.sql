-- لوحة مؤشرات تطبيق العملاء (للإدارة): تسجيل، حجوزات، إتمام/عدم حضور، إنفاق، ولاء، تجربة القصات، تقييمات، شكاوى، تحويل لعملاء فعليين.
-- قراءة فقط من بيانات الصالون الحقيقية ومبتغيّرش أي حاجة. آمن لو اتشغّل أكتر من مرة.
create or replace function public.app_kpis(p_days int default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_days int := least(greatest(coalesce(p_days, 30), 7), 365); v_from timestamptz := now() - make_interval(days => v_days); v_res jsonb;
begin
  if not (is_mgr() or has_perm('view_reports')) then raise exception 'غير مصرح'; end if;
  with ap as (select a.*, c.user_id is not null as is_app from appointments a left join customers c on c.id = a.customer_id where a.created_at >= v_from),
  inv as (select i.total, c.user_id is not null as is_app from invoices i join customers c on c.id = i.customer_id where i.created_at >= v_from)
  select jsonb_build_object(
    'days', v_days,
    'users', jsonb_build_object('total', (select count(*) from customers where user_id is not null),
        'new', (select count(*) from customers where user_id is not null and created_at >= v_from),
        'active', (select count(distinct customer_id) from ap where is_app),
        'all_customers', (select count(*) from customers)),
    'conversion', jsonb_build_object('app_users', (select count(*) from customers where user_id is not null),
        'with_invoice', (select count(*) from customers c where c.user_id is not null and exists (select 1 from invoices i where i.customer_id = c.id))),
    'bookings', jsonb_build_object('total', (select count(*) from ap),
        'by_source', coalesce((select jsonb_object_agg(s, n) from (select coalesce(booking_source, '؟') s, count(*) n from ap group by 1) x), '{}'::jsonb),
        'done', (select count(*) from ap where status::text = 'done'), 'no_show', (select count(*) from ap where status::text = 'no_show'),
        'cancelled', (select count(*) from ap where status::text = 'cancelled'), 'upcoming', (select count(*) from ap where status::text = 'upcoming'),
        'app_done', (select count(*) from ap where booking_source = 'app' and status::text = 'done'),
        'app_no_show', (select count(*) from ap where booking_source = 'app' and status::text = 'no_show'),
        'app_cancelled', (select count(*) from ap where booking_source = 'app' and status::text = 'cancelled')),
    'spend', jsonb_build_object('app_avg', (select round(avg(total), 1) from inv where is_app), 'app_n', (select count(*) from inv where is_app),
        'other_avg', (select round(avg(total), 1) from inv where not is_app), 'other_n', (select count(*) from inv where not is_app)),
    'loyalty', jsonb_build_object('redeemed', (select count(*) from loyalty_redemptions where created_at >= v_from),
        'used', (select count(*) from loyalty_redemptions where created_at >= v_from and status::text = 'used'),
        'customers', (select count(distinct customer_id) from loyalty_redemptions where created_at >= v_from)),
    'tryon', jsonb_build_object('total', (select count(*) from tryon_log where created_at >= v_from), 'ok', (select count(*) from tryon_log where created_at >= v_from and ok),
        'customers', (select count(distinct customer_id) from tryon_log where created_at >= v_from)),
    'reviews', jsonb_build_object('n', (select count(*) from reviews where created_at >= v_from), 'avg', (select round(avg(rating), 2) from reviews where created_at >= v_from),
        'avg_service', (select round(avg(service_rating), 2) from reviews where created_at >= v_from), 'avg_place', (select round(avg(place_rating), 2) from reviews where created_at >= v_from)),
    'feedback', jsonb_build_object('total', (select count(*) from customer_feedback where created_at >= v_from),
        'complaints', (select count(*) from customer_feedback where created_at >= v_from and kind = 'complaint'),
        'complaints_open', (select count(*) from customer_feedback where created_at >= v_from and kind = 'complaint' and coalesce(status, 'new') <> 'done'),
        'replied', (select count(*) from customer_feedback where created_at >= v_from and reply is not null)),
    'data_since', (select min(created_at) from appointments)
  ) into v_res;
  return v_res;
end $$;
revoke all on function public.app_kpis(int) from public, anon;
grant execute on function public.app_kpis(int) to authenticated, service_role;
notify pgrst, 'reload schema';
