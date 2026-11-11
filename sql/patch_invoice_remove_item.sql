-- ============================================================================
-- patch_invoice_remove_item.sql — حذف خدمة أو منتج من فاتورة (للمالك/المدير)
--   invoice_remove_item(p_invoice, p_item, p_force)
--   بيعمل في عملية واحدة:
--   • يمسح البند ويعيد حساب المجموع (الخصم ما يعدّيش المجموع، والإكرامية/الزيادة زي ما هي)
--   • total = اللي اتحصّل فعلاً (الإجمالي − الخصم − غير المدفوع + الزيادة): بيتحسب من جديد، والباقي المستحق ما يعدّيش المطلوب الجديد
--   • لو البند منتج: يرجّع الكمية للمخزون ويسجّل حركة مخزون
--   • لو العميل أخد نقاط على الفاتورة: يقلّل النقاط بنسبة المجموع الجديد (ونفس التخفيض في نقاطه الإجمالية)
--   • لو اليوم اتقفل: يرجّع needs_force، ولو أكّدت يحدّث لقطة القفل (p32_refresh_closing)
--   • يسجّل البند المحذوف في deletion_log (وسجل التدقيق بيتسجّل لوحده من الـ trigger)
--   مينفعش يمسح آخر بند (احذف الفاتورة كلها بدلها).
-- ============================================================================

create or replace function public.invoice_remove_item(p_invoice bigint, p_item bigint, p_force boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public'
as $fn$
declare
  i invoices; it invoice_items; v_led loyalty_ledger;
  v_day date; v_closed boolean := false; v_n int;
  v_sub numeric; v_disc numeric; v_total numeric; v_unpaid numeric;
  v_old_base numeric; v_new_base numeric; v_new_pts int; v_diff int := 0;
  v_restored boolean := false; v_aff boolean := p11_cfg_bool('disc_affects_points', true);
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if i.settles_invoice is not null then raise exception 'دي فاتورة سداد دين، مينفعش تتعدّل'; end if;
  select * into it from invoice_items where id = p_item and invoice_id = p_invoice for update;
  if not found then raise exception 'البند مش موجود في الفاتورة دي'; end if;
  select count(*) into v_n from invoice_items where invoice_id = p_invoice;
  if v_n <= 1 then raise exception 'ده آخر بند في الفاتورة. لو عايز تلغيها احذف الفاتورة كلها'; end if;

  -- يوم الفاتورة (نفس تعريف invoice_set_paid): لو اتقفل لازم تأكيد
  select b.day into v_day from business_days b where b.closed_at is not null and i.created_at < b.closed_at order by b.closed_at limit 1;
  v_closed := v_day is not null and exists (select 1 from cash_closings c where c.day = v_day);
  if v_closed and not coalesce(p_force, false) then
    return jsonb_build_object('removed', false, 'needs_force', true, 'day', v_day);
  end if;

  -- total في الفاتورة = اللي اتحصّل فعلاً = (الإجمالي − الخصم − غير المدفوع) + الزيادة/الإكرامية
  v_sub    := greatest(i.subtotal - it.unit_price * it.qty, 0);
  v_disc   := least(coalesce(i.discount, 0), v_sub);
  v_unpaid := least(coalesce(i.unpaid, 0), v_sub - v_disc);
  v_total  := (v_sub - v_disc - v_unpaid) + coalesce(i.extra_paid, 0);

  -- المخزون: المنتج يرجع
  if it.item_type = 'product' and it.item_id is not null then
    update products set stock = stock + it.qty where id = it.item_id;
    v_restored := found;
    if v_restored then
      insert into stock_movements(product_id, qty, reason) values (it.item_id, it.qty, 'void');
    end if;
  end if;

  -- نقاط الولاء: تقليل بنسبة المجموع الجديد
  if i.customer_id is not null then
    select * into v_led from loyalty_ledger where invoice_id = i.id and reason = 'purchase' order by id limit 1;
    if found and v_led.points > 0 then
      v_old_base := case when v_aff then i.total else i.subtotal end;
      v_new_base := case when v_aff then v_total else v_sub end;
      if v_old_base > 0 then
        v_new_pts := floor(v_led.points * least(v_new_base / v_old_base, 1))::int;
        v_diff := v_led.points - v_new_pts;
        if v_diff > 0 then
          update loyalty_ledger set points = v_new_pts, note = coalesce(note, '') || ' (اتعدّلت: اتحذف بند من الفاتورة)' where id = v_led.id;
          update customers set points = greatest(points - v_diff, 0), lifetime_points = greatest(lifetime_points - v_diff, 0) where id = i.customer_id;
        end if;
      end if;
    end if;
  end if;

  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
  values ('invoice_items', it.id::text, to_jsonb(it),
          jsonb_build_object('invoice_id', i.id, 'invoice_no', i.no, 'old_total', i.total, 'new_total', v_total,
                             'stock_restored', v_restored, 'points_reduced', v_diff, 'day_was_closed', v_closed), auth.uid());

  delete from invoice_items where id = it.id;
  update invoices set subtotal = v_sub, discount = v_disc, total = v_total, unpaid = v_unpaid where id = i.id;

  if v_closed then perform p32_refresh_closing(v_day, 'invoice_remove_item #' || i.no); end if;

  return jsonb_build_object('removed', true, 'no', i.no, 'item', it.name, 'old_total', i.total, 'new_total', v_total,
                            'stock_restored', v_restored, 'points_reduced', v_diff, 'refreshed_day', case when v_closed then v_day end);
end $fn$;

revoke all on function public.invoice_remove_item(bigint, bigint, boolean) from public, anon;
grant execute on function public.invoice_remove_item(bigint, bigint, boolean) to authenticated;
