-- patch_customer_premium.sql — تطبيق العميل البريميوم:
-- صورة العميل · تاريخ الميلاد وهدية عيد الميلاد · "كرّر آخر زيارة"
-- التحكم من الإعدادات ← الولاء: birthday_enabled (تشغيل/إيقاف) و birthday_points (الافتراضي 50).
-- آمن للتشغيل أكتر من مرة.

alter table public.customers
  add column if not exists avatar text,
  add column if not exists birthday date,
  add column if not exists birthday_gift_year int;

create or replace function public.my_profile()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare c customers; v_on boolean; v_pts int; v_ok boolean := false; b date;
begin
  select * into c from customers where user_id = auth.uid();
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  v_on := coalesce((select (value #>> '{}') <> 'false' from app_settings where key = 'birthday_enabled'), true);
  v_pts := coalesce((select nullif(value #>> '{}','')::numeric from app_settings where key = 'birthday_points' and jsonb_typeof(value) = 'number'), 50)::int;
  if v_on and v_pts > 0 and c.birthday is not null and coalesce(c.birthday_gift_year, 0) <> extract(year from current_date)::int
     and exists (select 1 from invoices i where i.customer_id = c.id) then
    -- من 3 أيام قبل لحد 7 أيام بعد عيد الميلاد
    b := make_date(extract(year from current_date)::int, extract(month from c.birthday)::int, least(extract(day from c.birthday)::int, 28));
    v_ok := current_date between b - 3 and b + 7;
  end if;
  return jsonb_build_object('name', c.name, 'avatar', c.avatar, 'birthday', c.birthday,
    'birthday_enabled', v_on, 'birthday_points', v_pts, 'can_claim_birthday', v_ok);
end $$;

create or replace function public.set_my_profile(p_avatar text default null, p_birthday date default null, p_remove_avatar boolean default false)
returns void language plpgsql security definer set search_path to 'public' as $$
declare c customers;
begin
  select * into c from customers where user_id = auth.uid() for update;
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  if p_remove_avatar then update customers set avatar = null where id = c.id; end if;
  if p_avatar is not null then
    if p_avatar !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_avatar) > 120000 then raise exception 'الصورة غير صالحة أو كبيرة'; end if;
    update customers set avatar = p_avatar where id = c.id;
  end if;
  if p_birthday is not null then
    if p_birthday < date '1930-01-01' or p_birthday > current_date - 5 * 365 then raise exception 'تاريخ الميلاد غير صحيح'; end if;
    update customers set birthday = p_birthday where id = c.id;
  end if;
end $$;

create or replace function public.claim_birthday_gift()
returns int language plpgsql security definer set search_path to 'public' as $$
declare c customers; v_pts int; b date;
begin
  select * into c from customers where user_id = auth.uid() for update;
  if c.id is null then raise exception 'مفيش حساب عميل'; end if;
  if not coalesce((select (value #>> '{}') <> 'false' from app_settings where key = 'birthday_enabled'), true) then raise exception 'هدية عيد الميلاد متوقفة دلوقتي'; end if;
  v_pts := coalesce((select nullif(value #>> '{}','')::numeric from app_settings where key = 'birthday_points' and jsonb_typeof(value) = 'number'), 50)::int;
  if c.birthday is null then raise exception 'ضيف تاريخ ميلادك الأول'; end if;
  if coalesce(c.birthday_gift_year, 0) = extract(year from current_date)::int then raise exception 'استلمت هدية السنة دي'; end if;
  if not exists (select 1 from invoices i where i.customer_id = c.id) then raise exception 'الهدية متاحة بعد أول زيارة'; end if;
  b := make_date(extract(year from current_date)::int, extract(month from c.birthday)::int, least(extract(day from c.birthday)::int, 28));
  if current_date not between b - 3 and b + 7 then raise exception 'مش معاد الهدية لسه'; end if;
  update customers set birthday_gift_year = extract(year from current_date)::int where id = c.id;
  if v_pts > 0 then perform add_points(c.id, v_pts, 'birthday', null, 'هدية عيد ميلاد'); end if;
  return v_pts;
end $$;

-- آخر زيارة خلصت: عشان زرار "كرّر آخر زيارة"
create or replace function public.my_last_visit()
returns jsonb language sql stable security definer set search_path to 'public' as $$
  select (select jsonb_build_object(
      'id', a.id, 'day', a.day, 'barber_id', a.barber_id, 'barber_name', pr.full_name,
      'service_ids', coalesce((select jsonb_agg(s2.service_id order by s2.service_id) from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id and sv.active), '[]'::jsonb),
      'services', coalesce((select string_agg(sv.name, ' + ') from appointment_services s2 join services sv on sv.id = s2.service_id where s2.appointment_id = a.id), ''))
    from appointments a left join profiles pr on pr.id = a.barber_id
    where a.status = 'done' and a.customer_id in (select c.id from customers c where c.user_id = auth.uid())
    order by a.day desc nulls last, a.id desc limit 1) $$;

revoke all on function public.my_profile() from public, anon;
revoke all on function public.set_my_profile(text,date,boolean) from public, anon;
revoke all on function public.claim_birthday_gift() from public, anon;
revoke all on function public.my_last_visit() from public, anon;
grant execute on function public.my_profile() to authenticated;
grant execute on function public.set_my_profile(text,date,boolean) to authenticated;
grant execute on function public.claim_birthday_gift() to authenticated;
grant execute on function public.my_last_visit() to authenticated;
