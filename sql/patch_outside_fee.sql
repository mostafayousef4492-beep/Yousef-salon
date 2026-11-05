-- «داخل المحل / خارج المحل» في الكاشير:
--  • داخل المحل = سعر الخدمات بس. خارج المحل = بيتضاف بند «خدمة خارج المحل» بمبلغ ثابت تحدده من الإعدادات (app_settings.outside_fee).
--  • البند بيتضاف على الفاتورة زي رسوم المستعجل (item_id = 0)، ومش داخل في حساب خصم الباقة: إجمالي = سعر الباقة + المبلغ.
--  • pos_checkout_b بقى فيه p_outside (الغلاف الموجود). العمولة بتتحسب على إجمالي الفاتورة زي أي بند.
-- لازم patch_walkin_bundles.sql يكون اتشغّل الأول. آمن للتكرار.
begin;
do $$
declare d text; n text; i1 int;
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  if position('app.pos_outside' in d) > 0 then return; end if;
  n := d;
  i1 := position('-- خصم الباقة' in n);
  if i1 = 0 or position('app.pos_bundle' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع — شغّل patch_walkin_bundles.sql الأول'; end if;
  n := substr(n, 1, i1 - 1) || $b$-- خدمة خارج المحل (مبلغ ثابت من الإعدادات)
  declare v_of numeric := greatest(p11_cfg_num('outside_fee', 0), 0);
  begin
    if coalesce(current_setting('app.pos_outside', true), '') = '1' and v_of > 0 then
      insert into invoice_items(invoice_id, item_type, item_id, name, qty, unit_price) values (v_inv, 'service', 0, 'خدمة خارج المحل', 1, round(v_of, 2));
      v_sub := v_sub + round(v_of, 2);
    end if;
  end;

  $b$ || substr(n, i1);
  execute n;
end $$;

drop function if exists public.pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint);
create or replace function public.pos_checkout_b(p_bundle bigint, p_cafe jsonb, p_customer bigint, p_barber uuid, p_items jsonb,
  p_discount_pct numeric, p_discount_fixed numeric, p_method text, p_appointment bigint default null, p_redemption bigint default null,
  p_request bigint default null, p_outside boolean default false)
returns bigint language plpgsql security definer set search_path = public as $$
declare r bigint;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if p_bundle is not null and not exists (select 1 from bundles where id = p_bundle and active) then raise exception 'الباقة مش متاحة'; end if;
  perform set_config('app.pos_bundle', coalesce(p_bundle::text, ''), true);
  perform set_config('app.pos_outside', case when coalesce(p_outside, false) then '1' else '' end, true);
  if p_cafe is not null and jsonb_typeof(p_cafe) = 'array' and jsonb_array_length(p_cafe) > 0 then
    r := pos_checkout_cafe(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request, p_cafe);
  else
    r := pos_checkout(p_customer, p_barber, p_items, p_discount_pct, p_discount_fixed, p_method, p_appointment, p_redemption, p_request);
  end if;
  perform set_config('app.pos_bundle', '', true);
  perform set_config('app.pos_outside', '', true);
  return r;
end $$;
revoke all on function public.pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint, boolean) from public, anon;
grant execute on function public.pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint, boolean) to authenticated;
commit;
