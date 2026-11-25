-- patch_material_auto_cost.sql — خامة مربوطة بخدمة تتخصم تكلفتها تلقائي من عمولة الصنايعي (مثلًا كيس الحنة مع الصبغة)
-- الربط (خدمة ↔ خامة ↔ كمية) كان بيخصم من المخزون بس. الملف بيضيف خيار على الخامة: «تكلفتها تتخصم قبل نسبة الصنايعي».
-- لما الخيار يتفعّل، أول ما الخدمة المربوطة تتسجّل في فاتورة: تكلفة (سعر الوحدة × الكمية المربوطة × كمية الخدمة) بتتخصم من الأساس
-- اللي بتتحسب عليه عمولة الصنايعي، والباقي يتقسم زي العادي. سعر الفاتورة للعميل مابيتغيّرش.
-- الخصم مش بيزيد عن سعر بند الخدمة نفسه (عمولة الصنايعي مابتبقاش بالسالب).
-- الخامات اللي الخيار فيها مطفي (الافتراضي) بتفضل زي ما هي بالظبط: مخزون بس. آمن للتشغيل أكتر من مرة.
-- لازم patch_materials.sql و patch_optional_materials.sql يكونوا متشغّلين.
do $$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'invoice_items' and column_name = 'mat_cost') then
    raise exception 'شغّل patch_optional_materials.sql الأول';
  end if;
end $$;

alter table public.materials add column if not exists cost_in_commission boolean not null default false;

create or replace function public.trg_material_use() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_cost numeric;
begin
  if new.item_type = 'service' then
    insert into material_movements(material_id, qty, reason, invoice_id, invoice_item_id, created_by)
    select sm.material_id, -(sm.qty * greatest(coalesce(new.qty,1),1)), 'service', new.invoice_id, new.id, auth.uid()
      from service_materials sm join materials m on m.id = sm.material_id and m.active
     where sm.service_id = new.item_id;
    select coalesce(sum(round(m.cost * sm.qty * greatest(coalesce(new.qty,1),1), 2)), 0) into v_cost
      from service_materials sm join materials m on m.id = sm.material_id and m.active and m.cost_in_commission
     where sm.service_id = new.item_id;
    if v_cost > 0 then
      update invoice_items set mat_cost = mat_cost + least(v_cost, greatest(coalesce(new.unit_price,0) * greatest(coalesce(new.qty,1),1), 0)) where id = new.id;
    end if;
  end if;
  return new;
end $$;

create or replace function public.material_set_cost_commission(p_id bigint, p_on boolean) returns void
language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not (is_mgr() or has_perm('restock')) then raise exception 'غير مصرح'; end if;
  update materials set cost_in_commission = coalesce(p_on, false) where id = p_id;
  if not found then raise exception 'الخامة مش موجودة'; end if;
end $fn$;
revoke all on function public.material_set_cost_commission(bigint, boolean) from public, anon;
grant execute on function public.material_set_cost_commission(bigint, boolean) to authenticated;
-- تراجع: update materials set cost_in_commission = false; (الفواتير اللي اتسجّلت قبل كده بتفضل بتكلفتها)
--         ولو عايز ترجّع الـ trigger القديم: شغّل trg_material_use من patch_materials.sql
