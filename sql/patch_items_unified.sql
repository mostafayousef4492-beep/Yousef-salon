-- patch_items_unified.sql — شاشة واحدة للأصناف والمخزون.
-- الصنف = علبة (فيها كام جرام/مللي/قطعة) + سعر شراء العلبة + سعر البيع (اختياري) + استهلاك كل خدمة + مجموعة (لو فيه أنواع بديلة).
-- بيتبني على النظام الحالي (products + materials المربوطة بـ product_id) من غير ما يمسح أو يغيّر بيانات قديمة.
-- بيحتاج: patch_shared_stock.sql و patch_purchase_all_types.sql (والأخير بيتحدّث هنا: record_purchase_v2).
-- اللي بيضيفه:
--   1) products.for_sale: صنف للاستهلاك بس (مش بيظهر في الكاشير).
--   2) item_save: إنشاء/تعديل صنف كامل مرة واحدة (علبة، جرامات، أسعار، مجموعة، استهلاك الخدمات).
--   3) item_from_material: تحويل خامة قديمة مش مربوطة (زي «واكس سينيور») لصنف بعلبة وسعر شراء صح، بنفس رصيدها.
--   4) item_issue: صرف للمحل: بينقّص المخزون وبيتسجّل في حركة الاستهلاك (reason = issue).
--   5) item_count: جرد صنف (علب كاملة + اللي في العبوة المفتوحة). التسجيل في حركة المخزون.
--   6) record_purchase_v2: بند منتج ممكن يبقى «صنف جديد» بتفاصيله (اسم، عبوة، سعر البيع، مجموعة) من فاتورة الشراء نفسها.
--   7) items_consumption(from,to): تقرير الاستهلاك (خدمات + صرف للمحل) بالكمية والتكلفة.
-- آمن لو اتشغّل أكتر من مرة.

do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'materials' and column_name = 'product_id') then
    raise exception 'شغّل patch_shared_stock.sql الأول';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'materials' and column_name = 'group_name') then
    raise exception 'شغّل patch_purchase_all_types.sql الأول';
  end if;
end $$;

alter table public.products add column if not exists for_sale boolean not null default true;

-- ===== الجوهر: إنشاء/تعديل صنف (بدون فحص صلاحية: للاستعمال الداخلي) =====
create or replace function public.item_save_core(p_id bigint, p_name text, p_unit text, p_pack numeric, p_cost numeric, p_price numeric, p_for_sale boolean,
                                                  p_min numeric, p_group text, p_consumable boolean, p_consumption jsonb)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id bigint := p_id; v_name text := btrim(coalesce(p_name, '')); v_unit text := coalesce(nullif(btrim(coalesce(p_unit, '')), ''), 'قطعة');
        v_pack numeric := coalesce(p_pack, 1); v_mid bigint; p products; r jsonb; v_q numeric; v_grp text := nullif(btrim(coalesce(p_group, '')), '');
begin
  if v_name = '' then raise exception 'اكتب اسم الصنف'; end if;
  if v_pack <= 0 or v_pack > 1000000 then raise exception 'محتوى العلبة غلط'; end if;
  if coalesce(p_cost, 0) < 0 or coalesce(p_price, 0) < 0 or coalesce(p_min, 0) < 0 then raise exception 'الأسعار والحد الأدنى لازم أرقام موجبة'; end if;
  if exists (select 1 from products x where lower(btrim(x.name)) = lower(v_name) and not x.archived and x.id is distinct from v_id) then
    raise exception 'فيه صنف بنفس الاسم «%»', v_name;
  end if;
  if v_id is null then
    insert into products(name, price, cost, stock, min_stock, for_sale)
      values (v_name, coalesce(p_price, 0), coalesce(p_cost, 0), 0, round(coalesce(p_min, 0))::int, coalesce(p_for_sale, true)) returning id into v_id;
  else
    update products set name = v_name, price = coalesce(p_price, 0), cost = coalesce(p_cost, 0), min_stock = round(coalesce(p_min, 0))::int, for_sale = coalesce(p_for_sale, true)
     where id = v_id and not archived;
    if not found then raise exception 'الصنف مش موجود'; end if;
  end if;
  select * into p from products where id = v_id;
  select id into v_mid from materials where product_id = v_id;
  if coalesce(p_consumable, false) then
    if v_mid is null then
      insert into materials(name, unit, stock, min_stock, cost, active, product_id, pack_size, open_qty, group_name)
        values (v_name, v_unit, p.stock * v_pack, p.min_stock * v_pack, round(p.cost / v_pack, 3), true, v_id, v_pack, 0, v_grp) returning id into v_mid;
    else
      update materials set name = v_name, unit = v_unit, pack_size = v_pack, open_qty = least(open_qty, v_pack),
             stock = p.stock * v_pack + least(open_qty, v_pack), cost = round(p.cost / v_pack, 3), min_stock = p.min_stock * v_pack, group_name = v_grp, active = true
       where id = v_mid;
    end if;
    for r in select * from jsonb_array_elements(coalesce(p_consumption, '[]'::jsonb)) loop
      v_q := (r->>'qty')::numeric;
      if v_q is null or v_q < 0 or v_q > 1000000 then raise exception 'كمية الاستهلاك غلط'; end if;
      if v_q = 0 then delete from service_materials where service_id = (r->>'service_id')::bigint and material_id = v_mid;
      else insert into service_materials(service_id, material_id, qty) values ((r->>'service_id')::bigint, v_mid, v_q)
             on conflict (service_id, material_id) do update set qty = excluded.qty;
      end if;
    end loop;
  elsif v_mid is not null then          -- اتشال الاستهلاك: الخامة بتتوقف وتتشال من الخدمات
    delete from service_materials where material_id = v_mid;
    update materials set active = false, optional = false where id = v_mid;
  end if;
  return v_id;
end $$;
revoke all on function public.item_save_core(bigint, text, text, numeric, numeric, numeric, boolean, numeric, text, boolean, jsonb) from public, anon, authenticated;

create or replace function public.item_save(p_id bigint, p_name text, p_unit text, p_pack numeric, p_cost numeric, p_price numeric, p_for_sale boolean,
                                            p_min numeric, p_group text, p_consumable boolean, p_consumption jsonb default '[]'::jsonb)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not is_mgr() then raise exception 'للمالك أو المدير بس'; end if;
  return item_save_core(p_id, p_name, p_unit, p_pack, p_cost, p_price, p_for_sale, p_min, p_group, p_consumable, p_consumption);
end $$;

-- ===== تحويل خامة قديمة (مش مربوطة بصنف) لصنف: الرصيد بيتحوّل لعلب + عبوة مفتوحة، والسعر بسعر العلبة =====
create or replace function public.item_from_material(p_material bigint, p_pack numeric, p_pack_cost numeric, p_price numeric, p_for_sale boolean default false)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare m materials; v_pid bigint; v_boxes int; v_open numeric; v_stock numeric;
begin
  if not is_mgr() then raise exception 'للمالك أو المدير بس'; end if;
  if p_pack is null or p_pack <= 0 or p_pack > 1000000 then raise exception 'محتوى العلبة غلط'; end if;
  if coalesce(p_pack_cost, -1) < 0 then raise exception 'سعر شراء العلبة غلط'; end if;
  select * into m from materials where id = p_material and not coalesce(archived, false) for update;
  if not found then raise exception 'الخامة مش موجودة'; end if;
  if m.product_id is not null then raise exception 'الخامة دي مربوطة بصنف بالفعل'; end if;
  if exists (select 1 from products x where lower(btrim(x.name)) = lower(btrim(m.name)) and not x.archived) then raise exception 'فيه صنف بنفس الاسم «%»', m.name; end if;
  v_stock := greatest(m.stock, 0);
  v_boxes := floor(v_stock / p_pack)::int;
  v_open := v_stock - v_boxes * p_pack;
  insert into products(name, price, cost, stock, min_stock, for_sale)
    values (m.name, coalesce(p_price, 0), p_pack_cost, v_boxes, ceil(greatest(m.min_stock, 0) / p_pack)::int, coalesce(p_for_sale, false)) returning id into v_pid;
  insert into stock_movements(product_id, qty, reason) select v_pid, v_boxes, 'restock' where v_boxes > 0;
  update materials set product_id = v_pid, pack_size = p_pack, open_qty = v_open, cost = round(p_pack_cost / p_pack, 3),
         min_stock = ceil(greatest(min_stock, 0) / p_pack) * p_pack, stock = v_boxes * p_pack + v_open where id = p_material;
  return v_pid;
end $$;

-- ===== صرف للمحل: بينقّص من المخزون وبيتسجّل استهلاك (reason = issue) =====
create or replace function public.item_issue(p_material bigint, p_qty numeric, p_note text default null)
returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare m materials;
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'اكتب كمية أكبر من صفر'; end if;
  select * into m from materials where id = p_material and not coalesce(archived, false);
  if not found then raise exception 'الصنف مش موجود'; end if;
  if m.stock < p_qty then raise exception 'الرصيد (% %) مش كفاية', round(m.stock, 3), m.unit; end if;
  insert into material_movements(material_id, qty, reason, note, created_by) values (p_material, -p_qty, 'issue', coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'صرف للمحل'), auth.uid());
  return m.stock - p_qty;
end $$;

-- ===== جرد صنف مربوط: علب كاملة + جرامات العبوة المفتوحة =====
create or replace function public.item_count(p_product bigint, p_boxes int, p_open numeric default 0, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare p products; m materials; v_open numeric := coalesce(p_open, 0); d int;
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if p_boxes is null or p_boxes < 0 then raise exception 'عدد العلب غلط'; end if;
  select * into p from products where id = p_product and not archived for update;
  if not found then raise exception 'الصنف مش موجود'; end if;
  select * into m from materials where product_id = p_product for update;
  if found then
    if v_open < 0 or v_open >= m.pack_size then raise exception 'المفتوح لازم يكون أقل من محتوى العلبة (% %)', m.pack_size, m.unit; end if;
    update materials set open_qty = v_open, stock = p_boxes * pack_size + v_open where id = m.id;
  end if;
  d := p_boxes - p.stock;
  if d <> 0 then
    update products set stock = p_boxes where id = p_product;
    insert into stock_movements(product_id, qty, reason) values (p_product, d, 'count');
  end if;
end $$;

-- ===== تقرير الاستهلاك (خدمات + صرف للمحل) =====
create or replace function public.items_consumption(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_tz text := my_tz();
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'cost')::numeric desc) from (
    select jsonb_build_object('id', m.id, 'name', m.name, 'unit', m.unit,
             'service_qty', coalesce(sum(-mm.qty) filter (where mm.reason = 'service'), 0) - coalesce(sum(mm.qty) filter (where mm.reason = 'service_void'), 0),
             'issue_qty', coalesce(sum(-mm.qty) filter (where mm.reason = 'issue'), 0),
             'cost', round(m.cost * (coalesce(sum(-mm.qty) filter (where mm.reason in ('service', 'issue')), 0) - coalesce(sum(mm.qty) filter (where mm.reason = 'service_void'), 0)), 2)) x
      from material_movements mm join materials m on m.id = mm.material_id
     where mm.reason in ('service', 'service_void', 'issue') and (mm.created_at at time zone v_tz)::date between p_from and p_to
     group by m.id, m.name, m.unit, m.cost) q), '[]'::jsonb);
end $$;

-- ===== فاتورة الشراء: بند منتج ممكن يكون «صنف جديد» =====
create or replace function public.record_purchase_v2(p_supplier bigint, p_date date, p_items jsonb, p_paid numeric, p_paid_from text, p_note text, p_update_cost boolean default false)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint; it jsonb; v_total numeric := 0; v_sup numeric := 0; v_qty numeric; v_cost numeric; v_name text; v_ty text; v_pid bigint; v_mid bigint; v_unit text;
        v_day date := coalesce(p_date, (now() at time zone my_tz())::date); v_kinds text[] := '{}'; v_kind text; v_mat materials; v_new jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_paid_from not in ('drawer', 'other') then raise exception 'مصدر الدفع غير صحيح'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'ضيف بند واحد على الأقل'; end if;
  if p_supplier is not null and not exists (select 1 from suppliers s where s.id = p_supplier) then raise exception 'المورد غير موجود'; end if;
  insert into purchases(supplier_id, bought_on, kind, total, paid, paid_from, note)
    values (p_supplier, v_day, 'mixed', 0, 0, p_paid_from, nullif(btrim(coalesce(p_note, '')), '')) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    v_ty := coalesce(it->>'type', 'product'); v_qty := (it->>'qty')::numeric; v_cost := (it->>'unit_cost')::numeric;
    v_pid := null; v_mid := null;
    if v_qty is null or v_qty <= 0 or v_cost is null or v_cost < 0 then raise exception 'الكمية والسعر لازم أرقام صحيحة'; end if;
    if v_ty = 'product' then
      v_new := it->'new_item';
      if v_new is not null and jsonb_typeof(v_new) = 'object' and btrim(coalesce(v_new->>'name', '')) <> '' then
        select id into v_pid from products where lower(btrim(name)) = lower(btrim(v_new->>'name')) and not archived limit 1;   -- نفس الاسم موجود: نزوّد عليه
        if v_pid is null then
          v_pid := item_save_core(null, v_new->>'name', v_new->>'unit', coalesce(nullif(v_new->>'pack', '')::numeric, 1), v_cost,
                                  coalesce(nullif(v_new->>'price', '')::numeric, 0), coalesce((v_new->>'for_sale')::boolean, false),
                                  coalesce(nullif(v_new->>'min', '')::numeric, 0), v_new->>'group', coalesce((v_new->>'consumable')::boolean, false), '[]'::jsonb);
        end if;
      else
        v_pid := nullif(it->>'product_id', '')::bigint;
      end if;
      if v_pid is null then raise exception 'اختار الصنف أو اكتب بيانات صنف جديد في كل بند'; end if;
      if v_qty <> trunc(v_qty) then raise exception 'كمية المنتج لازم تكون رقم صحيح'; end if;
      select pr.name into v_name from products pr where pr.id = v_pid;
      if v_name is null then raise exception 'منتج غير موجود'; end if;
      update products set stock = stock + v_qty::int where id = v_pid;
      insert into stock_movements(product_id, qty, reason) values (v_pid, v_qty::int, 'restock');
      if p_update_cost then update products set cost = v_cost where id = v_pid; end if;
    elsif v_ty = 'material' then
      v_new := it->'new_material';
      if v_new is not null and jsonb_typeof(v_new) = 'object' and btrim(coalesce(v_new->>'name', '')) <> '' then
        v_unit := coalesce(nullif(btrim(v_new->>'unit'), ''), 'قطعة');
        select * into v_mat from materials where lower(btrim(name)) = lower(btrim(v_new->>'name')) and not coalesce(archived, false) limit 1;
        if found then v_mid := v_mat.id;     -- نفس الاسم موجود: نزوّد عليه بدل ما نكرره
        else
          insert into materials(name, unit, min_stock, cost, active, group_name)
            values (btrim(v_new->>'name'), v_unit, 0, v_cost, true, nullif(btrim(coalesce(v_new->>'group', '')), '')) returning id into v_mid;
        end if;
      else
        v_mid := nullif(it->>'material_id', '')::bigint;
      end if;
      if v_mid is null then raise exception 'اختار الخامة أو اكتب اسم نوع جديد في كل بند'; end if;
      select * into v_mat from materials where id = v_mid;
      if not found then raise exception 'الخامة مش موجودة'; end if;
      if v_mat.product_id is not null then raise exception 'الخامة «%» رصيدها من المخزون: اشتريها كـ «منتج للبيع»', v_mat.name; end if;
      v_name := v_mat.name;
      insert into material_movements(material_id, qty, reason, note) values (v_mid, v_qty, 'restock', 'فاتورة شراء #' || v_id);
      if p_update_cost then update materials set cost = v_cost where id = v_mid; end if;
    elsif v_ty = 'supplies' then
      v_name := btrim(coalesce(it->>'name', ''));
      if v_name = '' then raise exception 'اكتب اسم كل بند'; end if;
      v_sup := v_sup + round(v_qty * v_cost, 2);
    else
      raise exception 'نوع البند غير صحيح';
    end if;
    insert into purchase_items(purchase_id, product_id, material_id, item_kind, name, qty, unit_cost) values (v_id, v_pid, v_mid, v_ty, v_name, v_qty, v_cost);
    v_total := v_total + round(v_qty * v_cost, 2);
    if not (v_ty = any (v_kinds)) then v_kinds := v_kinds || v_ty; end if;
  end loop;
  if v_total <= 0 then raise exception 'إجمالي الفاتورة لازم يكون أكبر من صفر'; end if;
  if p_paid is null or p_paid < 0 or p_paid > v_total then raise exception 'المدفوع لازم يكون من صفر لحد إجمالي الفاتورة'; end if;
  v_kind := case when array_length(v_kinds, 1) = 1 then (case v_kinds[1] when 'product' then 'stock' when 'material' then 'materials' else 'supplies' end) else 'mixed' end;
  update purchases set total = v_total, paid = p_paid, kind = v_kind where id = v_id;
  if v_sup > 0 then   -- المستلزمات بس بتتحسب مصروف (المنتجات والخامات بتتحسب تكلفة وقت البيع/الاستهلاك)
    insert into expenses(category, amount, note, spent_on, paid_from, supplier_id, purchase_id)
      values ('مستلزمات', v_sup, coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'مشتريات مستلزمات'), v_day, p_paid_from, p_supplier, v_id);
  end if;
  return v_id;
end $$;
revoke all on function public.record_purchase_v2(bigint, date, jsonb, numeric, text, text, boolean) from public, anon;
grant execute on function public.record_purchase_v2(bigint, date, jsonb, numeric, text, text, boolean) to authenticated;


do $$
declare f text;
begin
  foreach f in array array['item_save(bigint,text,text,numeric,numeric,numeric,boolean,numeric,text,boolean,jsonb)', 'item_from_material(bigint,numeric,numeric,numeric,boolean)',
                           'item_issue(bigint,numeric,text)', 'item_count(bigint,int,numeric,text)', 'items_consumption(date,date)',
                           'record_purchase_v2(bigint,date,jsonb,numeric,text,text,boolean)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
notify pgrst, 'reload schema';
