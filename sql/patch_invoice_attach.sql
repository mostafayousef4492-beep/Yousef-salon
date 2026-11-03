-- ربط عميل بفاتورة قديمة (كانت "عميل عابر") وحساب نقاطها وزيارتها
-- آمن للتشغيل أكتر من مرة. مفيش حاجة بتتعدل في الفواتير نفسها غير customer_id.
create or replace function public.invoice_attach_customer(p_invoice bigint, p_customer bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i invoices; v_c customers; v_mult numeric; v_pts int := 0; v_base numeric; v_every int; v_loy boolean := p11_cfg_bool('ff_loyalty',true); v_bonus int := 0;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if i.customer_id is not null then raise exception 'الفاتورة دي مربوطة بعميل بالفعل'; end if;
  select * into v_c from customers where id = p_customer for update;
  if not found then raise exception 'العميل مش موجود'; end if;
  update invoices set customer_id = p_customer where id = p_invoice;
  if v_loy then
    select t.mult into v_mult from loyalty_tier(v_c.lifetime_points) t;
    v_base := case when p11_cfg_bool('disc_affects_points',true) then i.total else i.subtotal end;
    v_pts := floor(v_base / greatest((setting('points_per_currency','10'::jsonb))::text::numeric,1) * coalesce(v_mult,1))::int;
    if v_pts > 0 then
      perform add_points(p_customer, v_pts, 'purchase', p_invoice, 'فاتورة قديمة #' || i.no);
      update loyalty_ledger set created_at = i.created_at where id = (select max(id) from loyalty_ledger where customer_id = p_customer and invoice_id = p_invoice and reason = 'purchase');
    end if;
  end if;
  update customers set visits = visits + 1 where id = p_customer;
  if v_loy then
    v_every := greatest((setting('visit_bonus_every','5'::jsonb))::text::int,1);
    if (v_c.visits + 1) % v_every = 0 then
      v_bonus := (setting('visit_bonus_points','100'::jsonb))::text::int;
      perform add_points(p_customer, v_bonus, 'visit', p_invoice, 'مكافأة ' || (v_c.visits + 1) || ' زيارة');
    end if;
  end if;
  return jsonb_build_object('points', v_pts, 'bonus', v_bonus, 'visits', v_c.visits + 1, 'name', v_c.name);
end $$;
revoke all on function public.invoice_attach_customer(bigint,bigint) from public, anon;
grant execute on function public.invoice_attach_customer(bigint,bigint) to authenticated;
