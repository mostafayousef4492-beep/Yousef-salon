-- أوفلاين المرحلة 2: فاتورة أوفلاين بمنتجات + خصم (في حدود الكاشير) + كاش/كارت/محفظة (بمرجع يدوي).
-- بتكمّل pos_checkout_offline (الخدمات بس) من غير ما تلمسها. شغّل patch_offline_checkout.sql الأول (لو ما اتشغّلش).
-- كل حاجة بتتنفّذ بنفس pos_checkout الأصلية (نفس قواعد الخصم والمخزون والعمولة)، وبعدها بنقارن الإجمالي النهائي
-- بالإجمالي اللي الكاشير شافه أوفلاين: لو اختلف (سعر اتغيّر/خصم اتغيّر) بنلغي العملية كلها وتفضل معلّقة للمراجعة.
-- خصم فوق حدّ الكاشير بيحتاج موافقة المدير أونلاين، فمش بيتقبل هنا (pos_checkout بترفضه).
-- الباقات وخصم الشركات والكوفي والخامات والحجز والدفع الجزئي لسه أونلاين بس.
-- آمن لو اتشغّل أكتر من مرة.

create or replace function public.pos_checkout_offline2(
  p_request_id uuid, p_barber uuid, p_items jsonb, p_local_total numeric, p_sold_at timestamptz,
  p_method text, p_pay_channel text, p_pay_ref text, p_discount_pct numeric, p_discount_fixed numeric
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user uuid := auth.uid(); v_resp jsonb; v_id bigint; v_total numeric; v_note text;
  v_pct numeric := coalesce(p_discount_pct, 0); v_fx numeric := coalesce(p_discount_fixed, 0);
begin
  if v_user is null or not can_use_pos() then raise exception 'غير مصرح'; end if;
  if p_request_id is null or p_local_total is null or p_local_total <= 0 then raise exception 'بيانات الفاتورة غير مكتملة'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'الفاتورة لازم تحتوي خدمة أو منتج'; end if;
  if exists (select 1 from jsonb_array_elements(p_items) x
              where x->>'type' not in ('service', 'product') or coalesce((x->>'qty')::int, 0) < 1
                 or (x->>'type' = 'service' and (x->>'qty')::int <> 1) or (x->>'qty')::int > 99) then
    raise exception 'المزامنة الأوفلاين تدعم الخدمات والمنتجات فقط';
  end if;
  if p_method not in ('cash', 'card', 'wallet') then raise exception 'طريقة دفع غير مدعومة'; end if;
  if v_pct < 0 or v_pct > 100 or v_fx < 0 then raise exception 'خصم غير صحيح'; end if;
  if v_pct > 0 and v_fx > 0 then raise exception 'نسبة وخصم ثابت مع بعض مش مدعوم'; end if;
  if p_method = 'wallet' and (coalesce(p_pay_channel, '') not in ('vodafone_cash', 'instapay', 'other_wallet') or length(trim(coalesce(p_pay_ref, ''))) < 4) then
    raise exception 'الدفع بالمحفظة محتاج القناة ومرجع العملية';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || p_request_id::text, 0));
  select response into v_resp from offline_checkout_receipts where request_id = p_request_id and created_by = v_user;
  if found then return v_resp; end if;
  if exists (select 1 from offline_checkout_receipts where request_id = p_request_id) then raise exception 'معرّف الفاتورة مستخدم بحساب آخر'; end if;

  v_id := pos_checkout(p_customer => null, p_barber => p_barber, p_items => p_items, p_discount_pct => v_pct,
                       p_discount_fixed => v_fx, p_method => p_method)::bigint;
  select total into v_total from invoices where id = v_id;
  if v_total is null or round(v_total, 2) <> round(p_local_total, 2) then
    raise exception 'الإجمالي اتغيّر (السعر أو الخصم): الجهاز كان %، والسيستم حسب %. راجع الفاتورة', p_local_total, v_total;
  end if;
  if p_method = 'wallet' then
    begin
      perform invoice_set_payment(v_id, p_pay_channel, trim(p_pay_ref));
    exception when others then
      v_note := 'الفاتورة اتسجلت لكن قناة/مرجع المحفظة ماتسجلوش: ' || sqlerrm;
    end;
  end if;
  v_resp := jsonb_build_object('invoice', v_id, 'note', v_note);
  insert into offline_checkout_receipts(request_id, created_by, response, sold_at)
    values (p_request_id, v_user, v_resp, case when p_sold_at <= now() then p_sold_at end);
  return v_resp;
end $$;
revoke all on function public.pos_checkout_offline2(uuid, uuid, jsonb, numeric, timestamptz, text, text, text, numeric, numeric) from public, anon;
grant execute on function public.pos_checkout_offline2(uuid, uuid, jsonb, numeric, timestamptz, text, text, text, numeric, numeric) to authenticated;
notify pgrst, 'reload schema';
