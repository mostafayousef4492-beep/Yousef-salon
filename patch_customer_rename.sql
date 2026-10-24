-- patch_customer_rename.sql — تعديل اسم العميل لو اتكتب غلط (مالك/مدير/كاشير/من عنده صلاحية إدارة الحجوزات)
-- بيغيّر الاسم بس: الرقم والنقاط والفواتير والحجوزات زي ما هي. العميل المربوط بحساب يشوف الاسم الجديد في الدور وعند الإدارة.
create or replace function public.admin_set_customer_name(p_customer bigint, p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare v_n text := btrim(coalesce(p_name, ''));
begin
  if not (is_mgr() or has_perm('use_pos') or has_perm('manage_appts')) then raise exception 'غير مصرح'; end if;
  if char_length(v_n) < 2 or char_length(v_n) > 60 then raise exception 'اكتب اسم العميل (من حرفين لـ 60 حرف)'; end if;
  update customers set name = v_n where id = p_customer;
  if not found then raise exception 'العميل مش موجود'; end if;
  return v_n;
end $$;
revoke all on function public.admin_set_customer_name(bigint, text) from public, anon;
grant execute on function public.admin_set_customer_name(bigint, text) to authenticated;
