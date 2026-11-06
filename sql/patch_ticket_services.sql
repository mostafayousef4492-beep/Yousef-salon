-- العميل (من لينك الحجز على واتساب) أو الموظف يختار/يغيّر خدمات تذكرته.
-- بيمسح الباقة المربوطة لو العميل غيّر الخدمات (الباقة بتتحدد تاني من الشاشة).
create or replace function public.set_ticket_services(p_id bigint, p_services bigint[], p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments; ok boolean; staff boolean;
begin
  if p_services is null or coalesce(array_length(p_services, 1), 0) = 0 then raise exception 'اختار خدمة واحدة على الأقل'; end if;
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  staff := is_mgr() or has_perm('manage_appts') or can_use_pos();
  ok := staff
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then raise exception 'غير مصرح'; end if;
  if a.status::text not in ('upcoming', 'checked_in') then raise exception 'مينفعش تغيّر الخدمات دلوقتي'; end if;
  if not exists (select 1 from services s where s.id = any(p_services) and s.active) then raise exception 'الخدمات مش متاحة'; end if;
  delete from appointment_services where appointment_id = p_id;
  insert into appointment_services(appointment_id, service_id)
    select p_id, s.id from services s where s.id = any(p_services) and s.active;
  update appointments set bundle_id = null where id = p_id and bundle_id is not null;
end $$;
revoke all on function public.set_ticket_services(bigint, bigint[], text) from public;
grant execute on function public.set_ticket_services(bigint, bigint[], text) to anon, authenticated;
-- للتراجع: drop function public.set_ticket_services(bigint, bigint[], text);
