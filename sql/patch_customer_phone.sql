-- تعديل رقم موبايل عميل عنده رقم بالفعل (من ملف العميل في تطبيق الإدارة).
-- لو الرقم الجديد مسجل لعميل تاني بيرفض ويقولك اسمه (الدمج بيتم بس من «ربط برقم موبايل» للعميل اللي مالوش رقم).
-- مش بيغيّر حساب دخول العميل. مفيش بيانات بتتمسح. آمن للتكرار.
create or replace function public.admin_set_customer_phone(p_customer bigint, p_phone text)
returns text language plpgsql security definer set search_path to 'public' as $$
declare v_ph text := regexp_replace(translate(coalesce(p_phone, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'), '\D', '', 'g'); s customers; t customers;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح (11 رقم ويبدأ بـ 01)'; end if;
  select * into s from customers where id = p_customer for update;
  if s.id is null then raise exception 'العميل مش موجود'; end if;
  if s.phone is not distinct from v_ph then return v_ph; end if;
  select * into t from customers where phone = v_ph and id <> s.id;
  if t.id is not null then raise exception 'الرقم ده مسجل لعميل تاني (%). مينفعش يتكرر.', t.name; end if;
  update customers set phone = v_ph where id = s.id;
  return v_ph;
end $$;
revoke all on function public.admin_set_customer_phone(bigint, text) from public, anon;
grant execute on function public.admin_set_customer_phone(bigint, text) to authenticated;
