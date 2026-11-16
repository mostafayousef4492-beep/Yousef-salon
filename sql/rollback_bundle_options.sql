-- تراجع عن patch_bundle_options.sql (الباقات اللي فيها خانات اختيار هتتعطّل لأنها مش هتتحسب).
-- 1) شيل أي باقة فيها خانات (أو عدّلها) قبل التراجع: select bundle_id from bundle_slots;
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  n := d;
  n := replace(n, 'select greatest(sum(ii.unit_price) - bb.price - sum(case when bi.base is not null then ii.unit_price - bi.base else 0 end), 0) into v_bd', 'select greatest(sum(ii.unit_price) - bb.price, 0) into v_bd');
  n := regexp_replace(n, 'cross join lateral bundle_eff\(bb\.id, \(select coalesce\(array_agg\(x\.item_id\), ''\{\}''\) from invoice_items x where x\.invoice_id = v_inv and x\.item_type = ''service''\)\) bi', 'join bundle_items bi on bi.bundle_id = bb.id');
  n := regexp_replace(n, 'not exists \(select 1 from bundle_eff\(bb\.id, \(select coalesce\(array_agg\(x\.item_id\), ''\{\}''\) from invoice_items x where x\.invoice_id = v_inv and x\.item_type = ''service''\)\) b2 where not exists', 'not exists (select 1 from bundle_items b2 where b2.bundle_id = bb.id and not exists');
  if position('bundle_eff(' in n) > 0 then raise exception 'مقدرتش أرجّع pos_checkout تلقائي'; end if;
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

create or replace function public.ticket_bundle(p_id bigint, p_phone text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a appointments; ok boolean; j jsonb;
begin
  select * into a from appointments where id = p_id;
  if not found or a.bundle_id is null then return null; end if;
  ok := is_mgr() or has_perm('manage_appts') or can_use_pos()
     or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
                or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then return null; end if;
  select jsonb_build_object('id', b.id, 'name', b.name, 'price', b.price, 'full', s.full, 'saving', greatest(s.full - b.price, 0), 'service_ids', s.ids)
    into j from bundles b cross join lateral (select coalesce(sum(sv.price), 0) as full, coalesce(jsonb_agg(sv.id order by sv.id), '[]'::jsonb) as ids from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id) s
   where b.id = a.bundle_id;
  return j;
end $$;

create or replace function public.set_ticket_bundle(p_id bigint, p_bundle bigint, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
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
end $$;

create or replace function public.bundles_list(p_all boolean default false)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.sort, x.id), '[]'::jsonb) from (
    select b.id, b.name, b.description, b.price, b.active, b.sort,
           s.full, greatest(s.full - b.price, 0) as saving, s.dur, s.items as services
      from bundles b
      cross join lateral (
        select coalesce(sum(sv.price), 0) as full, coalesce(sum(sv.duration_min), 0) as dur,
               jsonb_agg(jsonb_build_object('id', sv.id, 'name', sv.name, 'price', sv.price) order by sv.id) as items,
               bool_and(sv.active) as all_active
          from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id) s
     where (p_all and is_mgr()) or (b.active and s.all_active)
  ) x
$$;
revoke all on function public.bundles_list(boolean) from public;
grant execute on function public.bundles_list(boolean) to anon, authenticated;

drop function if exists public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[]);
create or replace function public.admin_save_bundle(p_id bigint, p_name text, p_desc text, p_price numeric, p_active boolean, p_services bigint[])
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := p_id; v_full numeric; v_n int; v_ids bigint[];
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_services, '{}')) x;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n < 2 then raise exception 'الباقة لازم فيها خدمتين على الأقل'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'اكتب اسم الباقة'; end if;
  select sum(price), count(*) into v_full, v_n from services where id = any(v_ids) and active;
  if v_n <> array_length(v_ids, 1) then raise exception 'فيه خدمة مش موجودة أو موقوفة'; end if;
  if p_price is null or p_price < 0 then raise exception 'سعر غير صحيح'; end if;
  if p_price >= v_full then raise exception 'سعر الباقة لازم يبقى أقل من مجموع الخدمات (%)', v_full; end if;
  if v_id is null then
    insert into bundles(name, description, price, active) values (btrim(p_name), nullif(btrim(coalesce(p_desc, '')), ''), p_price, coalesce(p_active, true)) returning id into v_id;
  else
    update bundles set name = btrim(p_name), description = nullif(btrim(coalesce(p_desc, '')), ''), price = p_price, active = coalesce(p_active, true) where id = v_id;
    if not found then raise exception 'الباقة مش موجودة'; end if;
    delete from bundle_items where bundle_id = v_id;
  end if;
  insert into bundle_items(bundle_id, service_id) select v_id, unnest(v_ids);
  return v_id;
end $$;
revoke all on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[]) from public, anon;
grant execute on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[]) to authenticated;
-- (جدول bundle_slots والدوال bundle_eff / bundle_saving بتفضل موجودة من غير ضرر)
