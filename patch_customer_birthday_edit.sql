-- تعديل تاريخ ميلاد العميل من الإدارة (المالك/المدير). null = مسح. العميل نفسه يعدّل من تطبيقه عن طريق set_my_profile الموجودة.
create or replace function public.admin_set_customer_birthday(p_customer bigint, p_birthday date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_birthday is not null and (p_birthday < date '1930-01-01' or p_birthday > current_date - 5 * 365) then raise exception 'تاريخ الميلاد غير صحيح'; end if;
  update customers set birthday = p_birthday where id = p_customer;
  if not found then raise exception 'العميل مش موجود'; end if;
end $$;
revoke all on function public.admin_set_customer_birthday(bigint, date) from public, anon;
grant execute on function public.admin_set_customer_birthday(bigint, date) to authenticated;
