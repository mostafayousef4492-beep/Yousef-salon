-- رجوع عن خصومات الشركات. بيشيل التعديل من pos_checkout ويمسح جداول الشركات.
-- تحذير: بيمسح أعمدة company_* من الفواتير (الخصم نفسه فضل محسوب جوه invoices.discount).
do $$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pos_checkout';
  if d like '%v_cd numeric%' then
    d := replace(d, ' v_cd numeric := 0; v_cmp companies; v_cid bigint; v_elig numeric;', '');
    d := regexp_replace(d, E'  -- خصم الشركة \\(اتفاق معتمد.*?(  -- قواعد الخصم \\(بعد معرفة الإجمالي\\))', E'\\1');
    d := replace(d, ' + v_bd + v_cd);', ' + v_bd);');
    d := replace(d, ', company_id = case when v_cd > 0 then v_cid end, company_discount = v_cd, company_approved_by = case when v_cd > 0 then auth.uid() end', '');
    assert d not like '%v_cd%', 'الرجوع ماكملش';
    execute d;
  end if;
end $$;
drop function if exists pos_checkout_b(bigint, jsonb, bigint, uuid, jsonb, numeric, numeric, text, bigint, bigint, bigint, boolean, bigint);
create or replace function pos_checkout_b(p_bundle bigint, p_cafe jsonb, p_customer bigint, p_barber uuid, p_items jsonb,
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
revoke all on function pos_checkout_b(bigint,jsonb,bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint,boolean) from public, anon;
grant execute on function pos_checkout_b(bigint,jsonb,bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint,boolean) to authenticated, service_role;
drop function if exists company_save(bigint,text,text,numeric,numeric,date,date,boolean,boolean,integer,text,bigint[]);
drop function if exists company_list(); drop function if exists company_by_code(text); drop function if exists company_link_customer(bigint,bigint);
drop function if exists company_join(text); drop function if exists my_company(); drop function if exists company_leave(); drop function if exists company_report(date,date);
alter table invoices drop column if exists company_id, drop column if exists company_discount, drop column if exists company_approved_by;
alter table customers drop column if exists company_id, drop column if exists company_linked_at, drop column if exists company_linked_by;
drop table if exists company_excluded_services; drop table if exists companies;
