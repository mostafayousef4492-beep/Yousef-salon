-- صنف للبيع وللاستهلاك في الخدمات برصيد واحد، والاستهلاك بوحدة تانية (جرام/مللي) والبيع بالقطعة.
-- الفكرة: الخامة بتتربط بالصنف (materials.product_id) وبيتحدد "الصنف الواحد فيه كام" (pack_size، مثلاً 500 جرام).
--   * رصيد الصنف (قطع) هو الأصل. البيع من الكاشير زي ما هو (مبنلمسوش).
--   * استهلاك الخدمة بيتخصم من "العبوة المفتوحة" (open_qty بالجرام). لو خلصت، بيتفتح قطعة جديدة من رصيد الصنف
--     وبتتسجل في stock_movements (reason = service_open). الرجوع (إلغاء فاتورة) بيرجّع الجرامات، ولو كمّلت عبوة كاملة بترجع قطعة (service_void).
--   * رصيد الخامة بالجرام = قطع الصنف × حجم العبوة + المفتوح، وبيتزامن تلقائي. تكلفة الجرام = تكلفة الصنف ÷ حجم العبوة.
--   * التوريد والجرد للصنف المربوط بيتعملوا من المخزون (الصنف) بس.
-- الاستهلاك مبيوقفش قفل الفاتورة لو الرصيد مش كفاية: بيوقف عند صفر.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّرش أي بيانات قديمة.

alter table public.materials add column if not exists product_id bigint references public.products(id);
alter table public.materials add column if not exists pack_size numeric(14,3) not null default 1 check (pack_size > 0);
alter table public.materials add column if not exists open_qty numeric(14,3) not null default 0 check (open_qty >= 0);
create unique index if not exists materials_product_uq on public.materials(product_id) where product_id is not null;

create or replace function public.trg_material_apply() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare m materials; v_pstock int; v_need numeric; v_k int; v_avail int; v_open numeric;
begin
  select * into m from materials where id = new.material_id for update;
  if m.product_id is null then
    update materials set stock = stock + new.qty where id = new.material_id;
    return new;
  end if;
  select stock into v_pstock from products where id = m.product_id for update;
  v_open := m.open_qty;
  if new.qty < 0 then
    v_need := -new.qty;
    if v_open >= v_need then
      v_open := v_open - v_need;
    else
      v_k := ceil((v_need - v_open) / m.pack_size)::int;
      v_avail := least(v_k, v_pstock);
      if v_avail > 0 then
        update products set stock = stock - v_avail where id = m.product_id;
        insert into stock_movements(product_id, qty, reason) values (m.product_id, -v_avail, 'service_open');
        v_pstock := v_pstock - v_avail;
      end if;
      v_open := greatest(v_open + v_avail * m.pack_size - v_need, 0);
    end if;
  else
    v_open := v_open + new.qty;
    if v_open >= m.pack_size then
      v_k := floor(v_open / m.pack_size)::int;
      update products set stock = stock + v_k where id = m.product_id;
      insert into stock_movements(product_id, qty, reason) values (m.product_id, v_k, 'service_void');
      v_pstock := v_pstock + v_k;
      v_open := v_open - v_k * m.pack_size;
    end if;
  end if;
  update materials set open_qty = v_open, stock = v_pstock * pack_size + v_open where id = m.id;
  return new;
end $$;

create or replace function public.trg_material_linked_guard() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.reason in ('restock', 'count', 'initial') and exists (select 1 from materials where id = new.material_id and product_id is not null) then
    raise exception 'الخامة دي مربوطة بصنف في المخزون: ورّد أو اجرد من شاشة المخزون';
  end if;
  return new;
end $$;
drop trigger if exists material_linked_guard on public.material_movements;
create trigger material_linked_guard before insert on public.material_movements for each row execute function public.trg_material_linked_guard();

-- أي تغيير في رصيد/تكلفة الصنف يتنسخ على الخامة المربوطة (بوحدة الاستهلاك)
create or replace function public.trg_product_sync_material() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  update materials set stock = new.stock * pack_size + open_qty, cost = round(new.cost / pack_size, 3) where product_id = new.id;
  return new;
end $$;
drop trigger if exists product_sync_material on public.products;
create trigger product_sync_material after update of stock, cost on public.products for each row execute function public.trg_product_sync_material();

-- ربط صنف بالاستهلاك: p_unit (جرام...) و p_pack (الصنف الواحد فيه كام) و p_consumption = [{"service_id":1,"qty":20}] (0 = شيل)
drop function if exists public.item_make_shared(bigint, jsonb);
create or replace function public.item_make_shared(p_product bigint, p_consumption jsonb default '[]'::jsonb, p_unit text default 'قطعة', p_pack numeric default 1)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare p products; v_mid bigint; r jsonb; v_q numeric; v_unit text := coalesce(nullif(btrim(p_unit), ''), 'قطعة'); v_pack numeric := coalesce(p_pack, 1);
begin
  if not is_mgr() then raise exception 'للمالك أو المدير بس'; end if;
  if v_pack <= 0 or v_pack > 1000000 then raise exception 'حجم العبوة غلط'; end if;
  select * into p from products where id = p_product;
  if not found then raise exception 'الصنف مش موجود'; end if;
  select id into v_mid from materials where product_id = p_product;
  if v_mid is null then
    insert into materials(name, unit, stock, min_stock, cost, active, product_id, pack_size, open_qty)
      values (p.name, v_unit, p.stock * v_pack, p.min_stock * v_pack, round(p.cost / v_pack, 3), true, p_product, v_pack, 0) returning id into v_mid;
  else
    update materials set unit = v_unit, pack_size = v_pack, stock = p.stock * v_pack + least(open_qty, v_pack), open_qty = least(open_qty, v_pack),
           cost = round(p.cost / v_pack, 3), min_stock = p.min_stock * v_pack where id = v_mid;
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_consumption, '[]'::jsonb)) loop
    v_q := (r->>'qty')::numeric;
    if v_q is null or v_q < 0 or v_q > 1000000 then raise exception 'كمية الاستهلاك غلط'; end if;
    if v_q = 0 then
      delete from service_materials where service_id = (r->>'service_id')::bigint and material_id = v_mid;
    else
      insert into service_materials(service_id, material_id, qty) values ((r->>'service_id')::bigint, v_mid, v_q)
        on conflict (service_id, material_id) do update set qty = excluded.qty;
    end if;
  end loop;
  return v_mid;
end $$;
revoke all on function public.item_make_shared(bigint, jsonb, text, numeric) from public, anon;
grant execute on function public.item_make_shared(bigint, jsonb, text, numeric) to authenticated, service_role;
notify pgrst, 'reload schema';
