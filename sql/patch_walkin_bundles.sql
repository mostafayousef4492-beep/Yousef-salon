-- الباقات لعميل عابر (من غير حجز) في الكاشير.
--  • pos_checkout بقت تقرأ الباقة من الحجز (زي الأول) أو من اختيار الكاشير (إعداد جلسة محلي للمعاملة دي بس).
--  • pos_checkout_b(p_bundle, p_cafe, ...نفس بارامترات pos_checkout) = غلاف بيحط الباقة وينده pos_checkout أو pos_checkout_cafe.
--  • نفس القواعد: كل خدمات الباقة لازم تكون في الفاتورة، والخصم بيتحسب على السيرفر، ومش بيتجمّع مع خصم يدوي.
-- آمن للتكرار.
begin;
do $$
declare d text; n text; i1 int; i2 int; blk text;
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  if position('app.pos_bundle' in d) > 0 then return; end if;
  n := d;
  if position('v_bd numeric := 0;' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (v_bd) — شغّل patch_bundles.sql الأول'; end if;
  n := replace(n, 'v_bd numeric := 0;', 'v_bd numeric := 0; v_bid bigint;');
  i1 := position('-- خصم الباقة' in n); i2 := position('-- قواعد الخصم (بعد معرفة الإجمالي)' in n);
  if i1 = 0 or i2 = 0 or i2 < i1 then raise exception 'pos_checkout مختلفة عن المتوقع (بلوك الباقة)'; end if;
  blk := $b$-- خصم الباقة (من الحجز، أو من اختيار الكاشير لعميل عابر)
  v_bid := coalesce(nullif(current_setting('app.pos_bundle', true), '')::bigint, (select ap.bundle_id from appointments ap where ap.id = p_appointment));
  if v_bid is not null then
    select greatest(sum(ii.unit_price) - bb.price, 0) into v_bd
      from bundles bb
      join bundle_items bi on bi.bundle_id = bb.id
      join invoice_items ii on ii.invoice_id = v_inv and ii.item_type = 'service' and ii.item_id = bi.service_id
     where bb.id = v_bid and (bb.active or p_appointment is not null)
       and not exists (select 1 from bundle_items b2 where b2.bundle_id = bb.id and not exists (select 1 from invoice_items i2 where i2.invoice_id = v_inv and i2.item_type = 'service' and i2.item_id = b2.service_id))
     group by bb.price;
    v_bd := coalesce(v_bd, 0);
    if v_bd > 0 and (v_pct > 0 or v_fx > 0) then raise exception 'الباقة مش بتتجمّع مع خصم تاني'; end if;
    if v_bd > 0 and p_redemption is not null and not p11_cfg_bool('disc_stack_coupon',true) then raise exception 'مينفعش باقة مع كوبون ولاء'; end if;
  end if;
  $b$;
  n := substr(n, 1, i1 - 1) || blk || substr(n, i2);
  execute n;
end $$;

create or replace function public.pos_checkout_b(p_bundle bigint, p_cafe jsonb, p_customer bigint, p_barber uuid, p_items jsonb,
  p_discount_pct numeric, p_discount_fixed numeric, p_method text, p_appointment bigint default null, p_redemption bigint default null, p_request bigint default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare r bigint;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if p_bundle is not null and not exists (select 1 from bundles where id = p_bundle and active) then raise exception 'الباقة مش متاحة'; end if;
  perform set_config('app.pos_bundle', coalesce(p_bundle::text, ''), true);
  if p_cafe is not null and jsonb_typeof(p_cafe) = 'array' and jsonb_array_length(p_cafe) > 0 then
    r := pos_checkout_cafe(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request, p_cafe);
  else
    r := pos_checkout(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request);
  end if;
  perform set_config('app.pos_bundle', '', true);
  return r;
end $$;
revoke all on function public.pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint) from public, anon;
grant execute on function public.pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint) to authenticated;
commit;
