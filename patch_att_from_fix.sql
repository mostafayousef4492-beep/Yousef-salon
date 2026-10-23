-- patch_att_from_fix.sql — منع تكرار حساب اليوم: راتب شهري + أجر يوم بالحضور (كشف الحساب والتقارير)
-- المشكلة: لو الموظف عليه "أجر يوم" في يوم، وفي نفس اليوم كان بيتحسب له راتب شهري (قبل تاريخ التحويل للحضور)،
-- اليوم بيتحسب مرتين. الحل: اليوم اللي فيه "أجر يوم" ما بيتحسبش له راتب شهري.
-- مفيش أي حركة بتتمسح أو بتتعدل، ومفيش تاريخ بيتغير: الأيام اللي مالهاش أجر يوم بتفضل زي ما هي بالظبط.
-- عدد الأيام المتكررة في فترة (يوم فيه أجر يوم وبرضه محسوب راتب شهري)
create or replace function public.p24_dup_days(p_staff uuid, p_from timestamptz, p_to timestamptz) returns integer
language sql stable security definer set search_path to 'public' as $$
  select count(*)::int
    from generate_series((p_from at time zone my_tz())::date, (p_to at time zone my_tz())::date - 1, interval '1 day') g(d)
   where exists (select 1 from staff_transactions w where w.staff_id = p_staff and w.kind::text = 'bonus' and w.note = 'أجر يوم ' || to_char(g.d, 'YYYY-MM-DD'))
     and not exists (select 1 from staff_pay_profile pp where pp.staff_id = p_staff and pp.att_from is not null
                       and g.d::date >= pp.att_from and (pp.att_to is null or g.d::date < pp.att_to))
$$;
revoke all on function public.p24_dup_days(uuid, timestamptz, timestamptz) from public, anon, authenticated;

-- الراتب الشهري المحسوب لفترة (بيستخدمه ملخص الموظف والتقارير) بعد خصم الأيام المتكررة
create or replace function public.salary_part_for(p_staff uuid, p_salary numeric, p_from timestamptz, p_to timestamptz) returns numeric
language plpgsql stable security definer set search_path to 'public' as $$
declare pf record; a timestamptz; b timestamptz; r numeric := 0; tz text := my_tz(); dup int; dim numeric;
begin
  select att_from, att_to into pf from staff_pay_profile where staff_id = p_staff;
  if not found or pf.att_from is null then
    r := salary_part(p_salary, p_from, p_to);
  else
    a := pf.att_from::timestamp at time zone tz;
    b := case when pf.att_to is null then null else pf.att_to::timestamp at time zone tz end;
    if p_from < a then r := r + salary_part(p_salary, p_from, least(p_to, a)); end if;
    if b is not null and p_to > b then r := r + salary_part(p_salary, greatest(p_from, b), p_to); end if;
  end if; /* p24_dedupe */
  dup := p24_dup_days(p_staff, p_from, p_to);
  if dup > 0 then
    dim := extract(day from (date_trunc('month', p_from at time zone tz) + interval '1 month' - interval '1 day'))::numeric;
    r := greatest(r - round(coalesce(p_salary, 0) * dup / dim, 2), 0);
  end if;
  return r;
end $$;

-- كشف الحساب: ما يضيفش "راتب يوم" في يوم فيه "أجر يوم"
do $$ declare d text; n text;
begin
  d := pg_get_functiondef('staff_statement(uuid,timestamptz,timestamptz)'::regprocedure);
  if position('p24_dedupe' in d) = 0 then
    n := replace(d, 'where coalesce(pr.salary, 0) > 0 and (g.d at time zone tz) < v_to /* p19_att_skip */',
      'where coalesce(pr.salary, 0) > 0 and (g.d at time zone tz) < v_to /* p19_att_skip */' || E'\n' ||
      '       and not exists (select 1 from staff_transactions w where w.staff_id = p_staff and w.kind::text = ''bonus'' and w.note = ''أجر يوم '' || to_char(g.d, ''YYYY-MM-DD'')) /* p24_dedupe */');
    if n = d or position('p24_dedupe' in n) = 0 then raise exception 'staff_statement: anchor not found'; end if;
    execute n;
  end if;
end $$;
