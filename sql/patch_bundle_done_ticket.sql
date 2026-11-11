-- حل: «مينفعش تغيّر الباقة دلوقتي» لما الكاشير يطبّق باقة/عرض على تذكرة الحلاق خلّصها (status = done) ولسه مفيش فاتورة.
-- التعديل: الموظف (مدير/كاشير/صلاحية الحجوزات) يقدر يضيف/يغيّر الباقة على تذكرة done بشرط مفيش فاتورة متسجلة عليها.
-- العميل نفسه لسه ممنوع، وأي تذكرة عليها فاتورة (أو ملغية/no_show) لسه ممنوعة. آمن للتكرار، مفيش بيانات بتتمسح.
create or replace function public.set_ticket_bundle(p_id bigint, p_bundle bigint, p_phone text default null)
returns void language plpgsql security definer set search_path to 'public' as $function$
declare a appointments; ok boolean; staff boolean; b bundles;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  staff := is_mgr() or has_perm('manage_appts') or can_use_pos();
  ok := staff
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then raise exception 'غير مصرح'; end if;
  if a.status::text not in ('upcoming', 'checked_in')
     and not (staff and a.status::text = 'in_service')
     and not (staff and a.status::text = 'done' and not exists (select 1 from invoices i where i.appointment_id = a.id)) then
    raise exception 'مينفعش تغيّر الباقة دلوقتي'; end if;
  if p_bundle is null then update appointments set bundle_id = null where id = p_id; return; end if;
  select * into b from bundles where id = p_bundle and active;
  if not found then raise exception 'الباقة مش متاحة'; end if;
  if not staff and exists (select 1 from bundle_items bi where bi.bundle_id = p_bundle
              and not exists (select 1 from appointment_services s where s.appointment_id = p_id and s.service_id = bi.service_id)) then
    raise exception 'خدمات الحجز مش مطابقة للباقة'; end if;
  update appointments set bundle_id = p_bundle where id = p_id;
end $function$;
