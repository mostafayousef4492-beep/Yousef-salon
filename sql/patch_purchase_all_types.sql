-- patch_purchase_all_types.sql — فاتورة شراء واحدة لكل الأنواع + مجموعات الخامات (أي نوع من المجموعة يتخصم).
-- 1) فاتورة الشراء: كل بند يختار نوعه: «منتج للبيع» (يزوّد مخزون المنتج) / «خامة» (يزوّد رصيد الخامة، وممكن تضيف خامة جديدة من نفس الشاشة) /
--    «مستلزم» (مصروف). والفاتورة الواحدة تقدر تجمع الأنواع كلها. الإلغاء بيرجّع المنتجات والخامات.
-- 2) مجموعة الخامة (materials.group_name): خامات من أكتر من نوع/ماركة ليها نفس المجموعة (مثلًا «ماسك صنفرة»).
--    الخدمة المربوطة بأي خامة من المجموعة بتسحب من أي نوع فيها: الأقدم الأول (الأقل رقمًا) اللي رصيده يكفي، ولو مش كفاية بتكمّل من اللي بعده.
--    الخامات من غير مجموعة شغلها زي ما هو بالظبط. اربط الخدمة بنوع واحد بس من المجموعة (لو ربطتها بأكتر من نوع في نفس المجموعة، بيتحسب الأكبر مش المجموع).
-- لازم patch_materials.sql و patch_optional_materials.sql (عمود mat_cost). آمن لو اتشغّل أكتر من مرة.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'invoice_items' and column_name = 'mat_cost') then
    raise exception 'شغّل patch_optional_materials.sql الأول';
  end if;
end $$;

alter table public.materials add column if not exists group_name text;
alter table public.materials add column if not exists cost_in_commission boolean not null default false;
create index if not exists materials_group_idx on public.materials (group_name) where group_name is not null;

alter table public.purchase_items add column if not exists material_id bigint references public.materials(id) on delete set null;
alter table public.purchase_items add column if not exists item_kind text;
alter table public.purchases drop constraint if exists purchases_kind_check;
alter table public.purchases add constraint purchases_kind_check check (kind in ('stock', 'supplies', 'materials', 'mixed'));

-- ---------- الاستهلاك مع مجموعات الخامات ----------
create or replace function public.trg_material_use() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_cost numeric := 0; v_mult numeric; rg record; mr record; v_need numeric; v_take numeric; v_first bigint;
begin
  if new.item_type = 'service' then
    v_mult := greatest(coalesce(new.qty, 1), 1);
    -- خامات من غير مجموعة: زي الأول
    insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
    select sm.material_id, -(sm.qty * v_mult), 'service', new.invoice_id, new.id, auth.uid()
      from service_materials sm join materials m on m.id = sm.material_id and m.active
     where sm.service_id = new.item_id and coalesce(btrim(m.group_name), '') = '';
    select coalesce(sum(round(m.cost * sm.qty * v_mult, 2)), 0) into v_cost
      from service_materials sm join materials m on m.id = sm.material_id and m.active and m.cost_in_commission
     where sm.service_id = new.item_id and coalesce(btrim(m.group_name), '') = '';
    -- خامات ليها مجموعة: بتتسحب من أي نوع في المجموعة
    for rg in select btrim(m.group_name) as gn, max(sm.qty) * v_mult as need
               from service_materials sm join materials m on m.id = sm.material_id and m.active
              where sm.service_id = new.item_id and coalesce(btrim(m.group_name), '') <> '' group by btrim(m.group_name) loop
      v_need := rg.need; v_first := null;
      for mr in select id, greatest(stock, 0) as avail, cost, cost_in_commission from materials
                where active and not coalesce(archived, false) and btrim(group_name) = rg.gn
                order by (stock >= v_need) desc, (stock > 0) desc, id loop
        if v_first is null then v_first := mr.id; end if;
        exit when v_need <= 0;
        v_take := least(v_need, mr.avail);
        if v_take > 0 then
          insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
            values (mr.id, -v_take, 'service', new.invoice_id, new.id, auth.uid());
          if mr.cost_in_commission then v_cost := v_cost + round(mr.cost * v_take, 2); end if;
          v_need := v_need - v_take;
        end if;
      end loop;
      if v_need > 0 and v_first is not null then   -- مفيش رصيد كفاية: الباقي على أول نوع (يطلع بالسالب زي الخامات العادية)
        insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
          values (v_first, -v_need, 'service', new.invoice_id, new.id, auth.uid());
        select case when cost_in_commission then round(cost * v_need, 2) else 0 end into v_take from materials where id = v_first;
        v_cost := v_cost + coalesce(v_take, 0);
      end if;
    end loop;
    if v_cost > 0 then
      update invoice_items set mat_cost = mat_cost + least(v_cost, greatest(coalesce(new.unit_price, 0) * v_mult, 0)) where id = new.id;
    end if;
  end if;
  return new;
end $$;

-- ---------- فاتورة شراء لكل الأنواع ----------
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
      v_pid := nullif(it->>'product_id', '')::bigint;
      if v_pid is null then raise exception 'اختار المنتج في كل بند'; end if;
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

-- إلغاء الفاتورة: يرجّع المنتجات والخامات
create or replace function public.void_purchase(p_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $$
declare r record;
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from purchases p where p.id = p_id) then raise exception 'فاتورة الشراء مش موجودة'; end if;
  for r in select x.product_id, x.qty from purchase_items x where x.purchase_id = p_id and x.product_id is not null loop
    update products set stock = stock - r.qty::int where id = r.product_id;
    insert into stock_movements(product_id, qty, reason) values (r.product_id, -r.qty::int, 'purchase_void');
  end loop;
  for r in select x.material_id, x.qty from purchase_items x where x.purchase_id = p_id and x.material_id is not null loop
    insert into material_movements(material_id, qty, reason, note) values (r.material_id, -r.qty, 'purchase_void', 'إلغاء فاتورة شراء #' || p_id);
  end loop;
  delete from purchases where id = p_id;
end $$;

-- حفظ مجموعة الخامة (المالك/المدير أو صلاحية restock). فاضي = من غير مجموعة.
create or replace function public.material_set_group(p_id bigint, p_group text)
returns void language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  update materials set group_name = nullif(btrim(coalesce(p_group, '')), '') where id = p_id;
  if not found then raise exception 'الخامة مش موجودة'; end if;
end $fn$;
revoke all on function public.material_set_group(bigint, text) from public, anon;
grant execute on function public.material_set_group(bigint, text) to authenticated;
notify pgrst, 'reload schema';
-- تراجع: drop function record_purchase_v2(...), material_set_group(...); والـ trigger القديم في patch_material_auto_cost.sql
