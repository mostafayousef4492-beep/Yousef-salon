-- التابلت: (1) الصنايعي يبدأ الخدمة بنفسه من التابلت (قابلة للإيقاف: الإعداد barber_can_start، الافتراضي true)
--          (2) ticket_bill: حساب التذكرة للعميل (قبل الدفع: الخدمات − الباقة + رسوم المستعجل، وبعد الدفع: إجمالي الفاتورة الفعلي).
-- آمن للتشغيل أكتر من مرة.

do $$
declare d text; o text := $o$if not (can_use_pos() or has_perm('manage_appts') or is_mgr()) then raise exception 'غير مصرح'; end if;$o$; n text;
begin
  select pg_get_functiondef('public.start_service(bigint)'::regprocedure) into d;
  if position('barber_can_start' in d) > 0 then return; end if;   -- اتطبّق قبل كده
  if position(o in d) = 0 then raise exception 'start_service مختلفة عن المتوقع، ابعتلي الرسالة دي'; end if;
  n := replace(d, o, $n$if not (can_use_pos() or has_perm('manage_appts') or is_mgr()
          or (p11_cfg_bool('barber_can_start', true) and has_perm('view_own_schedule')
              and exists (select 1 from appointments x where x.id = p_id and x.barber_id = auth.uid()))) then raise exception 'غير مصرح'; end if;$n$);
  execute n;
end $$;

create or replace function public.ticket_bill(p_id bigint, p_phone text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a appointments; ok boolean; inv invoices; v_sum numeric; v_save numeric := 0; v_fee numeric := 0; v_mult numeric := p11_cfg_num('urgent_multiplier', 2);
begin
  select * into a from appointments where id = p_id;
  if not found then return null; end if;
  ok := is_mgr() or has_perm('manage_appts') or can_use_pos()
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then return null; end if;
  select * into inv from invoices where appointment_id = p_id order by id desc limit 1;
  if found then
    return jsonb_build_object('paid', true, 'subtotal', inv.subtotal, 'discount', inv.discount, 'extra', inv.extra_paid, 'total', inv.total);
  end if;
  select coalesce(sum(sv.price), 0) into v_sum from appointment_services s join services sv on sv.id = s.service_id where s.appointment_id = p_id;
  if a.bundle_id is not null then
    select greatest(coalesce(sum(sv.price), 0) - b.price, 0) into v_save from bundles b
      join bundle_items bi on bi.bundle_id = b.id join services sv on sv.id = bi.service_id where b.id = a.bundle_id group by b.price;
    v_save := coalesce(v_save, 0);
  end if;
  if a.is_urgent and a.urgent_state = 'approved' then v_fee := v_sum * (v_mult - 1); end if;
  return jsonb_build_object('paid', false, 'subtotal', v_sum + v_fee, 'discount', v_save, 'urgent_fee', v_fee, 'total', greatest(v_sum + v_fee - v_save, 0));
end $$;
revoke all on function public.ticket_bill(bigint, text) from public;
grant execute on function public.ticket_bill(bigint, text) to anon, authenticated;
