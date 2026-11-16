-- ============================================================
-- الباقة بخيارات: «الخيار الأساسي» لكل خانة
-- المشكلة: باقة فيها «قصة شعر» ثابتة، لو العميل غيّر الخيار لـ«كلاسيك» الباقة كانت بتتشال.
-- الحل: الخانة (مجموعة الخيارات) بتفتكر الخيار اللي الباقة اتسعّرت عليه (base_service_id).
--   * العميل يغيّر الخيار براحته والباقة تفضل، وبيدفع الفرق بس (أغلى = يدفع الزيادة، أرخص = يوفّر الفرق).
--   * خصم الباقة بيفضل ثابت زي ما هو.
--   * الباقات الحالية اللي فيها خدمة بقت خيار (قصة شعر / حلاقة ذقن / استشوار / استشوار+مكوه) بتتحوّل لخانات تلقائي،
--     والخيار الأساسي هو الخدمة الأصلية، وبيتأكد إن خصم كل باقة ماتغيّرش (لو اتغيّر بيرفض ويرجّع كل حاجة).
-- لازم patch_bundle_options.sql و patch_menu_options.sql يكونوا اتشغّلوا قبله. آمن للتكرار.
-- ============================================================
alter table public.bundle_slots add column if not exists base_service_id bigint references public.services(id);

-- الخيار الأساسي الفعلي لخانة (الأساسي لو شغّال وفي المجموعة، وإلا أرخص خيار شغّال)
create or replace function public.bundle_slot_base(p_bundle bigint, p_group text)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(
    (select sv.id from bundle_slots bs join services sv on sv.id = bs.base_service_id
      where bs.bundle_id = p_bundle and bs.group_name = p_group and sv.group_name = p_group and sv.active),
    (select sv.id from services sv where sv.group_name = p_group and sv.active order by sv.price, sv.id limit 1))
$$;
revoke all on function public.bundle_slot_base(bigint, text) from public, anon, authenticated;

create or replace function public.bundle_eff(p_bundle bigint, p_ids bigint[])
returns table(service_id bigint, base numeric)
language sql stable security definer set search_path = public as $$
  select bi.service_id, null::numeric from bundle_items bi where bi.bundle_id = p_bundle
  union all
  select c.id, b.base
    from bundle_slots bs
    cross join lateral (select bundle_slot_base(bs.bundle_id, bs.group_name) as bid) bb
    cross join lateral (select sv.price as base from services sv where sv.id = bb.bid) b
    left join lateral (select sv.id from services sv where sv.group_name = bs.group_name and sv.active and sv.id = any(coalesce(p_ids, '{}'))
                        order by (sv.id = bb.bid) desc, sv.price, sv.id limit 1) c on true
   where bs.bundle_id = p_bundle
$$;
revoke all on function public.bundle_eff(bigint, bigint[]) from public, anon, authenticated;

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
               coalesce(jsonb_agg(jsonb_build_object('group', g.gname, 'base', g.bid, 'options', g.opts) order by g.gname), '[]'::jsonb) as slots,
               coalesce(bool_and(g.n > 0), true) as all_ok
          from (
            select bs.group_name as gname, bundle_slot_base(bs.bundle_id, bs.group_name) as bid,
                   (select coalesce(sv.price, 0) from services sv where sv.id = bundle_slot_base(bs.bundle_id, bs.group_name)) as base,
                   (select coalesce(sv.duration_min, 0) from services sv where sv.id = bundle_slot_base(bs.bundle_id, bs.group_name)) as dur,
                   (select count(*) from services sv where sv.group_name = bs.group_name and sv.active) as n,
                   (select coalesce(jsonb_agg(jsonb_build_object('id', sv.id, 'name', coalesce(sv.option_label, sv.name), 'price', sv.price, 'dur', sv.duration_min) order by sv.price, sv.id), '[]'::jsonb)
                      from services sv where sv.group_name = bs.group_name and sv.active) as opts
              from bundle_slots bs where bs.bundle_id = b.id) g) sl
     where (p_all and is_mgr()) or (b.active and f.all_active and sl.all_ok)
  ) x
$$;
revoke all on function public.bundles_list(boolean) from public;
grant execute on function public.bundles_list(boolean) to anon, authenticated;

-- حفظ باقة: p_bases = {"اسم المجموعة": رقم الخيار الأساسي} (اختياري؛ الافتراضي أرخص خيار)
drop function if exists public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[]);
create or replace function public.admin_save_bundle(p_id bigint, p_name text, p_desc text, p_price numeric, p_active boolean, p_services bigint[], p_groups text[] default '{}', p_bases jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint := p_id; v_full numeric; v_n int; v_ids bigint[]; v_gs text[]; g text; v_b bigint; v_bp numeric; v_bm jsonb := '{}'::jsonb;
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
    v_b := nullif(coalesce(p_bases, '{}'::jsonb) ->> g, '')::bigint;
    if v_b is null then select id into v_b from services where group_name = g and active order by price, id limit 1; end if;
    select price into v_bp from services where id = v_b and group_name = g and active;
    if v_bp is null then raise exception 'مجموعة «%» مفيهاش اختيارات شغّالة (أو الخيار الأساسي غلط)', g; end if;
    v_full := v_full + v_bp; v_bm := v_bm || jsonb_build_object(g, v_b);
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
  if v_gs is not null then insert into bundle_slots(bundle_id, group_name, base_service_id) select v_id, x, (v_bm ->> x)::bigint from unnest(v_gs) x; end if;
  return v_id;
end $$;
revoke all on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[], jsonb) from public, anon;
grant execute on function public.admin_save_bundle(bigint, text, text, numeric, boolean, bigint[], text[], jsonb) to authenticated;

-- ترحيل الباقات الحالية: أي خدمة ثابتة بقت خيار في مجموعة (واحدة بس من المجموعة في الباقة) تتحوّل لخانة أساسها هي نفسها.
-- بيتأكد إن خصم كل باقة هو هو؛ لو اتغيّر أي حاجة بيوقف ويرجّع كل حاجة.
do $$
declare r record; before jsonb; after jsonb;
begin
  select coalesce(jsonb_object_agg(b.id, bundle_saving(b.id)), '{}') into before from bundles b;
  for r in
    select bi.bundle_id, sv.group_name, min(bi.service_id) as sid
      from bundle_items bi join services sv on sv.id = bi.service_id
     where sv.group_name is not null
     group by bi.bundle_id, sv.group_name
    having count(*) = 1
  loop
    insert into bundle_slots(bundle_id, group_name, base_service_id) values (r.bundle_id, r.group_name, r.sid)
      on conflict (bundle_id, group_name) do update set base_service_id = excluded.base_service_id;
    delete from bundle_items where bundle_id = r.bundle_id and service_id = r.sid;
  end loop;
  select coalesce(jsonb_object_agg(b.id, bundle_saving(b.id)), '{}') into after from bundles b;
  if before is distinct from after then raise exception 'خصم باقة اتغيّر بعد الترحيل — اتلغى كل حاجة. قبل: % بعد: %', before, after; end if;
end $$;
