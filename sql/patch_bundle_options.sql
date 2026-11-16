-- ============================================================
-- باقات فيها «خدمة بخيارات» (مثلاً: قص الشعر ← كلاسيك / تدريج / ...)
-- الفكرة: الباقة بتاخد خدمات ثابتة + «خانات اختيار» (كل خانة = اسم مجموعة خيارات).
--   * العميل/الكاشير بيختار أي خيار شغّال من المجموعة وقت الحجز أو الدفع.
--   * الخصم ثابت مهما كان الخيار: خصم الباقة = (مجموع الخدمات الثابتة + أرخص خيار في كل خانة) − سعر الباقة.
--     يعني لو اختار خيار أغلى بيدفع الفرق، ومبيخسرش خصم الباقة.
--   * الباقات القديمة (من غير خانات) حسابها زي ما هو بالظبط.
-- مفيش جدول خدمات جديد: الخيارات هي خدمات عادية (services.group_name) ولازم تكون شغّالة.
-- آمن للتكرار. شغّله على Staging الأول، وبعد التجربة على الإنتاج بموافقتك. التراجع: sql/rollback_bundle_options.sql
-- ============================================================

create table if not exists public.bundle_slots (
  bundle_id bigint not null references public.bundles(id) on delete cascade,
  group_name text not null check (btrim(group_name) <> ''),
  primary key (bundle_id, group_name)
);
alter table public.bundle_slots enable row level security;
revoke all on public.bundle_slots from anon, authenticated;
grant select on public.bundle_slots to authenticated;
drop policy if exists bundle_slots_mgr_read on public.bundle_slots;
create policy bundle_slots_mgr_read on public.bundle_slots for select to authenticated using (is_mgr());

-- العناصر الفعلية لباقة على قايمة خدمات (فاتورة أو حجز): الثابتة + اختيار كل خانة (أرخص خيار موجود في القايمة).
-- خانة من غير اختيار بترجّع service_id = null (يعني الباقة مش مكتملة).  base = أرخص خيار شغّال في الخانة (null للثابت).
create or replace function public.bundle_eff(p_bundle bigint, p_ids bigint[])
returns table(service_id bigint, base numeric)
language sql stable security definer set search_path = public as $$
  select bi.service_id, null::numeric from bundle_items bi where bi.bundle_id = p_bundle
  union all
  select c.id, b.base
    from bundle_slots bs
    cross join lateral (select min(sv.price) as base from services sv where sv.group_name = bs.group_name and sv.active) b
    left join lateral (select sv.id from services sv where sv.group_name = bs.group_name and sv.active and sv.id = any(coalesce(p_ids, '{}')) order by sv.price, sv.id limit 1) c on true
   where bs.bundle_id = p_bundle
$$;
revoke all on function public.bundle_eff(bigint, bigint[]) from public, anon, authenticated;

-- خصم الباقة الثابت (بيتحسب على أسعار دلوقتي): ثابتة + أرخص خيار لكل خانة − سعر الباقة
create or replace function public.bundle_saving(p_bundle bigint)
returns numeric language sql stable security definer set search_path = public as $$
  select greatest(coalesce((select sum(sv.price) from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id), 0)
                + coalesce((select sum(x.base) from bundle_eff(b.id, '{}') x where x.base is not null), 0) - b.price, 0)
    from bundles b where b.id = p_bundle
$$;
revoke all on function public.bundle_saving(bigint) from public, anon, authenticated;

-- قايمة الباقات (+ slots: الخانات وخياراتها الشغّالة). services = الخدمات الثابتة بس (للتوافق مع النسخ القديمة).
create or replace function public.bundles_list(p_all boolean default false)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x.sort, x.id), '[]'::jsonb) from (
    select b.id, b.name, b.description, b.price, b.active, b.sort,
           (f.full + sl.base_sum) as full, greatest(f.full + sl.base_sum - b.price, 0) as saving,
           (f.dur + sl.dur_sum) as dur, f.items as services, sl.slots
      from bundles b
      cross join lateral (
        select coalesce(sum(sv.price), 0) as full, coalesce(sum(sv.duration_min), 0) as dur,
               coalesce(jsonb_agg(jsonb_build_object('id', sv.id, 'name', sv.name, 'price', sv.price) order by sv.id), '[]'::jsonb) as items,
               coalesce(bool_and(sv.active), true) as all_active
          from bundle_items bi join services sv on sv.id = bi.service_id where bi.bundle_id = b.id) f
      cross join lateral (
        select coalesce(sum(g.base), 0) as base_sum, coalesce(sum(g.dur), 0) as dur_sum,
               coalesce(jsonb_agg(jsonb_build_object('group', g.gname, 'options', g.opts) order by g.gname), '[]'::jsonb) as slots,
               coalesce(bool_and(g.n > 0), true) as all_ok
          from (
            select bs.group_name as gname,
                   (select coalesce(min(sv.price), 0) from services sv where sv.group_name = bs.group_name and sv.active) as base,
                   (select coalesce(min(sv.duration_min), 0) from services sv where sv.group_name = bs.group_name and sv.active) as dur,
                   (select count(*) from services sv where sv.group_name = bs.group_name and sv.active) as n,
                   (select coalesce(jsonb_agg(jsonb_build_object('id', sv.id, 'name', coalesce(sv.option_label, sv.name), 'price', sv.price, 'dur', sv.duration_min) order by sv.price, sv.id), '[]'::jsonb)
                      from services sv where sv.group_name = bs.group_name and sv.active) as opts
              from bundle_slots bs where bs.bundle_id = b.id) g) sl
     where (p_all and is_mgr()) or (b.active and f.all_active and sl.all_ok)
  ) x
$$;
revoke all on function public.bundles_list(boolean) from public;
grant execute on function public.bundles_list(boolean) to anon, authenticated;

-- حفظ باقة: p_services = خدمات ثابتة، p_groups = أسماء مجموعات الخيارات (كل مجموعة = خانة اختيار)
drop function if exists public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[]);
create or replace function public.admin_save_bundle(p_id bigint, p_name text, p_desc text, p_price numeric, p_active boolean, p_services bigint[], p_groups text[] default '{}')
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := p_id; v_full numeric; v_n int; v_ids bigint[]; v_gs text[]; g text; v_base numeric;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_services, '{}')) x;
  select array_agg(distinct btrim(x)) into v_gs from unnest(coalesce(p_groups, '{}')) x where btrim(coalesce(x, '')) <> '';
  v_n := coalesce(array_length(v_ids, 1), 0) + coalesce(array_length(v_gs, 1), 0);
  if v_n < 2 then raise exception 'الباقة لازم فيها خدمتين على الأقل'; end if;
  if char_length(btrim(coalesce(p_name, ''))) < 2 then raise exception 'اكتب اسم الباقة'; end if;
  v_full := 0;
  if coalesce(array_length(v_ids, 1), 0) > 0 then
    select coalesce(sum(price), 0), count(*) into v_full, v_n from services where id = any(v_ids) and active;
    if v_n <> array_length(v_ids, 1) then raise exception 'فيه خدمة مش موجودة أو موقوفة'; end if;
  end if;
  foreach g in array coalesce(v_gs, '{}') loop
    select min(price) into v_base from services where group_name = g and active;
    if v_base is null then raise exception 'مجموعة «%» مفيهاش اختيارات شغّالة — فعّل الاختيارات الأول', g; end if;
    v_full := v_full + v_base;
  end loop;
  if p_price is null or p_price < 0 then raise exception 'سعر غير صحيح'; end if;
  if p_price >= v_full then raise exception 'سعر الباقة لازم يبقى أقل من مجموع الخدمات (%)', v_full; end if;
  if v_id is null then
    insert into bundles(name, description, price, active) values (btrim(p_name), nullif(btrim(coalesce(p_desc, '')), ''), p_price, coalesce(p_active, true)) returning id into v_id;
  else
    update bundles set name = btrim(p_name), description = nullif(btrim(coalesce(p_desc, '')), ''), price = p_price, active = coalesce(p_active, true) where id = v_id;
    if not found then raise exception 'الباقة مش موجودة'; end if;
    delete from bundle_items where bundle_id = v_id;
    delete from bundle_slots where bundle_id = v_id;
  end if;
  if v_ids is not null then insert into bundle_items(bundle_id, service_id) select v_id, unnest(v_ids); end if;
  if v_gs is not null then insert into bundle_slots(bundle_id, group_name) select v_id, unnest(v_gs); end if;
  return v_id;
end $$;
revoke all on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[]) from public, anon;
grant execute on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[]) to authenticated;

-- ربط باقة بتذكرة: لازم الخدمات الثابتة كلها + اختيار واحد على الأقل من كل خانة (للعميل؛ الموظف زي ما كان)
create or replace function public.set_ticket_bundle(p_id bigint, p_bundle bigint, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments; ok boolean; staff boolean; b bundles; v_ids bigint[];
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
  select coalesce(array_agg(s.service_id), '{}') into v_ids from appointment_services s where s.appointment_id = p_id;
  if not staff and exists (select 1 from bundle_eff(p_bundle, v_ids) e where e.service_id is null or not (e.service_id = any(v_ids))) then
    raise exception 'خدمات الحجز مش مطابقة للباقة'; end if;
  update appointments set bundle_id = p_bundle where id = p_id;
end $$;

-- ملخص باقة التذكرة (service_ids = الثابتة، slots = الخانات وخياراتها)
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
  select jsonb_build_object('id', b.id, 'name', b.name, 'price', b.price, 'full', b.price + bundle_saving(b.id), 'saving', bundle_saving(b.id),
           'service_ids', coalesce((select jsonb_agg(bi.service_id order by bi.service_id) from bundle_items bi where bi.bundle_id = b.id), '[]'::jsonb),
           'slots', coalesce((select jsonb_agg(jsonb_build_object('group', bs.group_name,
                      'option_ids', (select coalesce(jsonb_agg(sv.id order by sv.id), '[]'::jsonb) from services sv where sv.group_name = bs.group_name and sv.active)) order by bs.group_name)
                      from bundle_slots bs where bs.bundle_id = b.id), '[]'::jsonb))
    into j from bundles b where b.id = a.bundle_id;
  return j;
end $$;

-- فاتورة التذكرة قبل الدفع (تقدير): خصم الباقة = bundle_saving
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
  if a.bundle_id is not null then v_save := coalesce(bundle_saving(a.bundle_id), 0); end if;
  if a.is_urgent and a.urgent_state = 'approved' then v_fee := v_sum * (v_mult - 1); end if;
  return jsonb_build_object('paid', false, 'subtotal', v_sum + v_fee, 'discount', v_save, 'urgent_fee', v_fee, 'total', greatest(v_sum + v_fee - v_save, 0));
end $$;

-- خصم الباقة في pos_checkout: تعديل 3 أسطر بس في حساب v_bd (باقي الدالة زي ما هي). بيفشل بوضوح لو الدالة مختلفة عن المتوقع.
do $$
declare d text; n text; arr text := $a$(select coalesce(array_agg(x.item_id), '{}') from invoice_items x where x.invoice_id = v_inv and x.item_type = 'service')$a$;
begin
  select pg_get_functiondef('public.pos_checkout(bigint,uuid,jsonb,numeric,numeric,text,bigint,bigint,bigint)'::regprocedure) into d;
  if position('bundle_eff(' in d) > 0 then return; end if;   -- اتطبّق قبل كده
  n := d;
  if position('select greatest(sum(ii.unit_price) - bb.price, 0) into v_bd' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (حساب الخصم)'; end if;
  n := replace(n, 'select greatest(sum(ii.unit_price) - bb.price, 0) into v_bd', 'select greatest(sum(ii.unit_price) - bb.price - sum(case when bi.base is not null then ii.unit_price - bi.base else 0 end), 0) into v_bd');
  if position('join bundle_items bi on bi.bundle_id = bb.id' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (عناصر الباقة)'; end if;
  n := replace(n, 'join bundle_items bi on bi.bundle_id = bb.id', 'cross join lateral bundle_eff(bb.id, ' || arr || ') bi');
  if position('not exists (select 1 from bundle_items b2 where b2.bundle_id = bb.id and not exists' in n) = 0 then raise exception 'pos_checkout مختلفة عن المتوقع (اكتمال الباقة)'; end if;
  n := replace(n, 'not exists (select 1 from bundle_items b2 where b2.bundle_id = bb.id and not exists', 'not exists (select 1 from bundle_eff(bb.id, ' || arr || ') b2 where not exists');
  execute n;
end $$;
