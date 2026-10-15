-- =====================================================================
-- patch_register_claim.sql — العميل اللي الكاشير سجّله (حجز إداري) يقدر يدخل بحسابه لما يفتح التطبيق
-- المشكلة: السجل بيتعمل بالموبايل من غير حساب، والعميل لما يسجّل كان بيتحوّل لطلب ربط محدش بيوافق عليه (مفيش شاشة ليه).
-- الحل: لو السجل مالوش حساب *ومالوش تاريخ* (نقاط/زيارات/فواتير) → يتربط فورًا بحساب العميل الجديد.
--        لو ليه تاريخ → يفضل طلب ربط بموافقة الكاشير/المدير (متاح في شاشة العملاء) أو كود دخول.
-- (اتجرّب على نسخة محلية فقط — جرّبه على branch الأول. التراجع: أعد تعريف register_customer من patch/النسخة القديمة.)
-- =====================================================================
create or replace function public.register_customer(p_name text, p_phone text)
returns bigint language plpgsql security definer set search_path to 'public'
as $$
declare v_ph text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g'); v_id bigint; v_uid uuid; v_mine bigint; v_pts int; v_vis int;
begin
  if auth.uid() is null then raise exception 'غير مسجل دخول'; end if;
  if v_ph !~ '^01[0-9]{9}$' then raise exception 'رقم الموبايل غير صحيح'; end if;
  select c.id into v_mine from customers c where c.user_id = auth.uid();
  if v_mine is not null then return v_mine; end if;
  perform pg_advisory_xact_lock(hashtextextended('p14ph:' || v_ph, 0));
  select c.id, c.user_id, coalesce(c.points,0) + coalesce(c.lifetime_points,0), coalesce(c.visits,0) into v_id, v_uid, v_pts, v_vis
    from customers c where c.phone = v_ph for update;
  if v_id is not null then
    if v_uid is not null then raise exception 'الرقم ده مسجل بحساب تاني'; end if;
    if v_pts = 0 and v_vis = 0 and not exists (select 1 from invoices i where i.customer_id = v_id) then
      update customers set user_id = auth.uid() where id = v_id and user_id is null;
      return v_id;
    end if;
    insert into claim_requests(customer_id, user_id) values (v_id, auth.uid()) on conflict do nothing;
    return 0;
  end if;
  insert into customers(user_id, name, phone) values (auth.uid(), coalesce(nullif(p_name,''), 'عميل'), v_ph) returning id into v_id;
  return v_id;
end $$;

-- قائمة طلبات الربط المعلّقة (للكاشير/المدير) — الموافقة بـ approve_claim الموجودة
create or replace function public.pending_claims()
returns table(id bigint, customer_id bigint, customer_name text, phone text, created_at timestamptz)
language plpgsql stable security definer set search_path to 'public'
as $$
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  return query select r.id, r.customer_id, c.name, c.phone, r.created_at
                 from claim_requests r join customers c on c.id = r.customer_id order by r.created_at;
end $$;
revoke all on function public.pending_claims() from public, anon;
grant execute on function public.pending_claims() to authenticated;
