-- مسح صنف المخزون: للمالك والمدير بس.
-- لو الصنف ملوش أي حركة مخزون ولا مشتريات بيتمسح نهائي. لو ليه حركة بيتأرشف (بيختفي من المخزون والكاشير
-- وسجل حركته وفواتيره القديمة بتفضل زي ما هي). في الحالتين بيتسجل صف في أرشيف المحذوفات.
-- آمن لو اتشغّل أكتر من مرة.
alter table public.products add column if not exists archived boolean not null default false;

create or replace function public.product_delete(p_id bigint)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare p products; v_used int;
begin
  if not is_mgr() then raise exception 'المسح للمالك أو المدير بس'; end if;
  select * into p from products where id = p_id and not archived for update;
  if not found then raise exception 'الصنف مش موجود'; end if;
  select (select count(*) from stock_movements where product_id = p_id) + (select count(*) from purchase_items where product_id = p_id) into v_used;
  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
    values ('products', p_id::text, to_jsonb(p), jsonb_build_object('used', v_used, 'mode', case when v_used = 0 then 'deleted' else 'archived' end), auth.uid());
  if v_used = 0 then
    delete from products where id = p_id;
    return 'deleted';
  end if;
  update products set archived = true, active = false where id = p_id;
  return 'archived';
end $$;
revoke all on function public.product_delete(bigint) from public, anon;
grant execute on function public.product_delete(bigint) to authenticated, service_role;
notify pgrst, 'reload schema';
