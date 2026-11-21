-- صنف للبيع وللاستهلاك في الخدمات برصيد واحد.
-- الفكرة: الخامة بتتربط بالصنف (materials.product_id). الرصيد الحقيقي دايمًا في products.stock:
--   * البيع من الكاشير زي ما هو (مبنلمسوش).
--   * استهلاك الخدمة للخامة المربوطة بيخصم من products.stock وبيتسجل في stock_movements (reason = service / service_void).
--   * رصيد الخامة المربوطة في شاشة الخامات بيتزامن تلقائيًا مع رصيد الصنف.
--   * التوريد والجرد للصنف المربوط بيتعملوا من المخزون (الصنف) بس.
-- قيود: الكمية بالقطعة الصحيحة (رصيد الأصناف أعداد صحيحة). الاستهلاك مبيوقفش قفل الفاتورة لو الرصيد مش كفاية: بيوقف عند صفر.
-- آمن لو اتشغّل أكتر من مرة، ومبيغيّرش أي بيانات قديمة. لو احتجت تتراجع: اعمل unlink من الخامة (update materials set product_id = null) وشغّل trg_material_apply القديمة.

alter table public.materials add column if not exists product_id bigint references public.products(id);
create unique index if not exists materials_product_uq on public.materials(product_id) where product_id is not null;

-- حركات الخامة: لو مربوطة بصنف، الخصم بيروح على رصيد الصنف
create or replace function public.trg_material_apply() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_pid bigint; v_q int;
begin
  select product_id into v_pid from materials where id = new.material_id;
  if v_pid is null then
    update materials set stock = stock + new.qty where id = new.material_id;
  else
    v_q := round(new.qty)::int;
    update products set stock = greatest(stock + v_q, 0) where id = v_pid;
    insert into stock_movements(product_id, qty, reason) values (v_pid, v_q, case when new.qty < 0 then 'service' else 'service_void' end);
  end if;
  return new;
end $$;

-- التوريد/الجرد على خامة مربوطة ممنوع (بيتعمل على الصنف)
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

-- أي تغيير في رصيد/تكلفة الصنف يتنسخ على الخامة المربوطة
create or replace function public.trg_product_sync_material() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  update materials set stock = new.stock, cost = new.cost where product_id = new.id;
  return new;
end $$;
drop trigger if exists product_sync_material on public.products;
create trigger product_sync_material after update of stock, cost on public.products for each row execute function public.trg_product_sync_material();

-- ربط صنف موجود بالاستهلاك: p_consumption = [{"service_id":1,"qty":1}, ...] (كميات صحيحة، 0 = شيل)
create or replace function public.item_make_shared(p_product bigint, p_consumption jsonb default '[]'::jsonb)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare p products; v_mid bigint; r jsonb; v_q numeric;
begin
  if not is_mgr() then raise exception 'للمالك أو المدير بس'; end if;
  select * into p from products where id = p_product;
  if not found then raise exception 'الصنف مش موجود'; end if;
  select id into v_mid from materials where product_id = p_product;
  if v_mid is null then
    insert into materials(name, unit, stock, min_stock, cost, active, product_id)
      values (p.name, 'قطعة', p.stock, p.min_stock, p.cost, true, p_product) returning id into v_mid;
  end if;
  for r in select * from jsonb_array_elements(coalesce(p_consumption, '[]'::jsonb)) loop
    v_q := (r->>'qty')::numeric;
    if v_q is null or v_q < 0 or v_q <> trunc(v_q) then raise exception 'كمية الاستهلاك لازم تكون عدد صحيح'; end if;
    if v_q = 0 then
      delete from service_materials where service_id = (r->>'service_id')::bigint and material_id = v_mid;
    else
      insert into service_materials(service_id, material_id, qty) values ((r->>'service_id')::bigint, v_mid, v_q)
        on conflict (service_id, material_id) do update set qty = excluded.qty;
    end if;
  end loop;
  return v_mid;
end $$;
revoke all on function public.item_make_shared(bigint, jsonb) from public, anon;
grant execute on function public.item_make_shared(bigint, jsonb) to authenticated, service_role;
notify pgrst, 'reload schema';
