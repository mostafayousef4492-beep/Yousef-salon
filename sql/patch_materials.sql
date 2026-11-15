-- ============================================================
-- خامات الخدمات: خصم استهلاك الخامات تلقائيًا من المخزون لما خدمة تتسجّل في فاتورة.
-- مفيش أي تعديل على دوال الدفع/الإلغاء الحالية (pos_checkout / checkout_invoice / admin_void_invoice):
--   * الخصم: trigger بعد إدخال بند خدمة في invoice_items (جوّه نفس عملية الدفع، يعني لو الدفع فشل الخصم بيتلغي).
--   * الرجوع: trigger قبل حذف البند (إلغاء الفاتورة أو حذف بند) بيسجّل حركة عكسية. مفيش حاجة بتتمسح من السجل.
-- الرصيد ممكن يبقى بالسالب (البيع ماينوقفش)، وبيظهر تنبيه لما يوصل للحد الأدنى.
-- آمن للتكرار. شغّله مرة واحدة في Supabase SQL Editor بعد مراجعته.
-- ============================================================
create table if not exists public.materials (
  id bigserial primary key,
  name text not null,
  unit text not null default 'قطعة',
  stock numeric(14,3) not null default 0,
  min_stock numeric(14,3) not null default 0,
  cost numeric(14,3) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists materials_name_uq on public.materials (lower(btrim(name)));

create table if not exists public.service_materials (
  service_id bigint not null references public.services(id) on delete cascade,
  material_id bigint not null references public.materials(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  primary key (service_id, material_id)
);

create table if not exists public.material_movements (
  id bigserial primary key,
  material_id bigint not null references public.materials(id),
  qty numeric(14,3) not null,                 -- موجب = دخل، سالب = خرج
  reason text not null,                       -- restock | service | service_void | count | initial
  invoice_id bigint,
  invoice_item_id bigint,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists material_mv_item_idx on public.material_movements (invoice_item_id);
create index if not exists material_mv_mat_idx on public.material_movements (material_id, created_at desc);

-- الرصيد = مجموع الحركات (مصدر واحد): أي حركة جديدة بتحدّث الرصيد
create or replace function public.trg_material_apply() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  update materials set stock = stock + new.qty where id = new.material_id;
  return new;
end $$;
drop trigger if exists material_apply on public.material_movements;
create trigger material_apply after insert on public.material_movements
  for each row execute function public.trg_material_apply();

-- سجل الحركات مايتعدّلش ولا يتمسح
create or replace function public.trg_material_immutable() returns trigger
language plpgsql as $$ begin raise exception 'سجل حركة الخامات مايتعدّلش — سجّل حركة عكسية'; end $$;
drop trigger if exists material_immutable on public.material_movements;
create trigger material_immutable before update or delete on public.material_movements
  for each row execute function public.trg_material_immutable();

-- الخصم عند تسجيل خدمة في الفاتورة
create or replace function public.trg_material_use() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.item_type = 'service' then
    insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
    select sm.material_id, -(sm.qty * greatest(coalesce(new.qty,1),1)), 'service', new.invoice_id, new.id, auth.uid()
      from service_materials sm join materials m on m.id = sm.material_id and m.active
     where sm.service_id = new.item_id;
  end if;
  return new;
end $$;
drop trigger if exists material_use on public.invoice_items;
create trigger material_use after insert on public.invoice_items
  for each row execute function public.trg_material_use();

-- الرجوع عند حذف بند أو إلغاء الفاتورة: حركة عكسية بصافي اللي اتخصم لنفس البند
create or replace function public.trg_material_return() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if old.item_type = 'service' then
    insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
    select mm.material_id, -sum(mm.qty), 'service_void', old.invoice_id, old.id, auth.uid()
      from material_movements mm where mm.invoice_item_id = old.id
     group by mm.material_id having sum(mm.qty) <> 0;
  end if;
  return old;
end $$;
drop trigger if exists material_return on public.invoice_items;
create trigger material_return before delete on public.invoice_items
  for each row execute function public.trg_material_return();

-- صلاحيات: القراءة للمدير/المالك/اللي معاه صلاحية التوريد، والكتابة عن طريق الدوال بس
alter table public.materials enable row level security;
alter table public.service_materials enable row level security;
alter table public.material_movements enable row level security;
drop policy if exists mat_read on public.materials;
create policy mat_read on public.materials for select to authenticated using (is_mgr() or has_perm('restock'));
drop policy if exists smat_read on public.service_materials;
create policy smat_read on public.service_materials for select to authenticated using (is_mgr() or has_perm('restock'));
drop policy if exists mmv_read on public.material_movements;
create policy mmv_read on public.material_movements for select to authenticated using (is_mgr() or has_perm('restock'));

-- دوال الإدارة
create or replace function public.material_save(p_id bigint, p_name text, p_unit text, p_min numeric, p_cost numeric, p_active boolean default true)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint;
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if btrim(coalesce(p_name,'')) = '' then raise exception 'اسم الخامة مطلوب'; end if;
  if coalesce(p_min,0) < 0 or coalesce(p_cost,0) < 0 then raise exception 'قيمة غلط'; end if;
  if p_id is null then
    insert into materials(name, unit, min_stock, cost, active) values (btrim(p_name), coalesce(nullif(btrim(p_unit),''),'قطعة'), coalesce(p_min,0), coalesce(p_cost,0), coalesce(p_active,true)) returning id into v_id;
  else
    update materials set name = btrim(p_name), unit = coalesce(nullif(btrim(p_unit),''),unit), min_stock = coalesce(p_min,0), cost = coalesce(p_cost,0), active = coalesce(p_active,true) where id = p_id returning id into v_id;
    if v_id is null then raise exception 'الخامة مش موجودة'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.material_restock(p_id bigint, p_qty numeric, p_note text default null)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if coalesce(p_qty,0) <= 0 then raise exception 'الكمية لازم تكون أكبر من صفر'; end if;
  insert into material_movements(material_id, qty, reason, note) values (p_id, p_qty, 'restock', p_note);
end $$;

-- جرد: بتكتب الكمية الفعلية، والنظام بيسجّل الفرق كحركة (مع سبب)
create or replace function public.material_count(p_id bigint, p_counted numeric, p_note text default null)
returns numeric language plpgsql security definer set search_path to 'public' as $$
declare v_cur numeric; v_diff numeric;
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  if coalesce(p_counted,-1) < 0 then raise exception 'الكمية غلط'; end if;
  select stock into v_cur from materials where id = p_id for update;
  if not found then raise exception 'الخامة مش موجودة'; end if;
  v_diff := p_counted - v_cur;
  if v_diff <> 0 then insert into material_movements(material_id, qty, reason, note) values (p_id, v_diff, 'count', p_note); end if;
  return v_diff;
end $$;

create or replace function public.service_material_set(p_service bigint, p_material bigint, p_qty numeric)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if coalesce(p_qty,0) <= 0 then
    delete from service_materials where service_id = p_service and material_id = p_material;
  else
    insert into service_materials(service_id, material_id, qty) values (p_service, p_material, p_qty)
    on conflict (service_id, material_id) do update set qty = excluded.qty;
  end if;
end $$;

grant execute on function public.material_save(bigint,text,text,numeric,numeric,boolean) to authenticated;
grant execute on function public.material_restock(bigint,numeric,text) to authenticated;
grant execute on function public.material_count(bigint,numeric,text) to authenticated;
grant execute on function public.service_material_set(bigint,bigint,numeric) to authenticated;
