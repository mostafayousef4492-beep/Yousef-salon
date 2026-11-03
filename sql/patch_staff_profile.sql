-- صورة وتاريخ ميلاد للموظفين. آمن للتشغيل أكتر من مرة.
alter table public.profiles add column if not exists avatar text, add column if not exists birthday date;

create or replace function public.staff_profile(p_staff uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_id uuid := coalesce(p_staff, auth.uid()); p profiles;
begin
  if v_id is distinct from auth.uid() and not is_mgr() then raise exception 'غير مصرح'; end if;
  select * into p from profiles where id = v_id;
  if not found then raise exception 'الموظف مش موجود'; end if;
  return jsonb_build_object('name', p.full_name, 'avatar', p.avatar, 'birthday', p.birthday);
end $$;

create or replace function public.set_staff_profile(p_staff uuid default null, p_avatar text default null, p_birthday date default null, p_remove_avatar boolean default false, p_clear_birthday boolean default false)
returns void language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid := coalesce(p_staff, auth.uid());
begin
  if v_id is distinct from auth.uid() and not is_owner() then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from profiles where id = v_id) then raise exception 'الموظف مش موجود'; end if;
  if p_remove_avatar then update profiles set avatar = null where id = v_id; end if;
  if p_avatar is not null then
    if p_avatar !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$' or length(p_avatar) > 120000 then raise exception 'الصورة غير صالحة أو كبيرة'; end if;
    update profiles set avatar = p_avatar where id = v_id;
  end if;
  if p_clear_birthday then update profiles set birthday = null where id = v_id; end if;
  if p_birthday is not null then
    if p_birthday < date '1930-01-01' or p_birthday > current_date - 5 * 365 then raise exception 'تاريخ الميلاد غير صحيح'; end if;
    update profiles set birthday = p_birthday where id = v_id;
  end if;
end $$;
revoke all on function public.staff_profile(uuid), public.set_staff_profile(uuid,text,date,boolean,boolean) from public, anon;
grant execute on function public.staff_profile(uuid), public.set_staff_profile(uuid,text,date,boolean,boolean) to authenticated;
