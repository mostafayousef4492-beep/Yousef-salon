-- مسح الخامة: للمالك والمدير بس.
-- لو الخامة ملهاش أي حركة بتتمسح نهائي. لو ليها حركة (توريد/خصم/جرد) بتتأرشف: بتختفي من الشاشات وبتتشال من استهلاك الخدمات،
-- وسجل حركتها القديم بيفضل زي ما هو (السجل ممنوع تعديله). في الحالتين بيتسجل صف في أرشيف المحذوفات.
-- آمن لو اتشغّل أكتر من مرة.
alter table public.materials add column if not exists archived boolean not null default false;

create or replace function public.material_delete(p_id bigint)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare m materials; v_mv int; v_open int;
begin
  if not is_mgr() then raise exception 'المسح للمالك أو المدير بس'; end if;
  select * into m from materials where id = p_id and not archived for update;
  if not found then raise exception 'الخامة مش موجودة'; end if;
  select count(*) into v_mv from material_movements where material_id = p_id;
  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
    values ('materials', p_id::text, to_jsonb(m), jsonb_build_object('movements', v_mv, 'mode', case when v_mv = 0 then 'deleted' else 'archived' end), auth.uid());
  delete from service_materials where material_id = p_id;
  if v_mv = 0 then
    delete from materials where id = p_id;
    return 'deleted';
  end if;
  update materials set archived = true, active = false,
         name = left(name, 80) || ' (محذوفة #' || id || ')' where id = p_id;
  return 'archived';
end $$;
revoke all on function public.material_delete(bigint) from public, anon;
grant execute on function public.material_delete(bigint) to authenticated, service_role;
notify pgrst, 'reload schema';
