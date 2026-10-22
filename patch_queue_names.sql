-- patch_queue_names.sql — الزبون يشوف أسامي اللي قبله في الطابور لحد دوره
-- الخصوصية: بيظهر الاسم الأول + أول حرف من الاسم التاني بس (مثال: "أحمد م."). مفيش أرقام ولا بيانات تانية.
-- إيقافه: في الإعدادات (queue_show_names) أو: update app_settings set value='false' where key='queue_show_names';
-- ترتيب اللي قدامه نفس منطق p11_ahead بالظبط، فالعدد والأسامي دايمًا متطابقين.
create or replace function public.p23_queue_names(p_id bigint) returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select case when coalesce((select value::text from app_settings where key = 'queue_show_names'), 'true') = 'false' then '[]'::jsonb
  else coalesce((
    select jsonb_agg(jsonb_build_object(
             'code', coalesce(a.ticket_code, '#' || a.ticket_no),
             'name', btrim(split_part(btrim(coalesce(c.name, 'عميل')), ' ', 1)
                     || coalesce(' ' || nullif(left(btrim(split_part(btrim(coalesce(c.name, '')), ' ', 2)), 1), '') || '.', '')),
             'status', a.status::text)
           order by a.sort_at, a.id)
    from appointments m
    join appointments a on a.id <> m.id and a.day = m.day
     and a.period::text is not distinct from m.period::text
     and (a.sort_at, a.id) < (m.sort_at, m.id)
     and a.status::text in ('upcoming','checked_in','in_service')
     and (m.barber_id is null or a.barber_id is null or a.barber_id = m.barber_id)
    left join customers c on c.id = a.customer_id
    where m.id = p_id), '[]'::jsonb) end
$$;
revoke all on function public.p23_queue_names(bigint) from public, anon, authenticated;

-- للزبون اللي حاجز من تطبيقه (حسابه)
create or replace function public.queue_names(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from appointments a join customers c on c.id = a.customer_id
                  where a.id = p_id and c.user_id = auth.uid()) then
    raise exception 'غير مصرح'; end if;
  return p23_queue_names(p_id);
end $$;
revoke all on function public.queue_names(bigint) from public, anon;
grant execute on function public.queue_names(bigint) to authenticated;

-- للزبون اللي بيتابع من صفحة الحجز (برقم الموبايل)
create or replace function public.public_queue_names(p_id bigint, p_phone text) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_ph text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  if length(v_ph) = 0 or not exists (select 1 from appointments a join customers c on c.id = a.customer_id
        where a.id = p_id and regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = v_ph) then
    raise exception 'غير مصرح'; end if;
  return p23_queue_names(p_id);
end $$;
revoke all on function public.public_queue_names(bigint, text) from public;
grant execute on function public.public_queue_names(bigint, text) to anon, authenticated;
