-- materials_vs_supplies(p_months): لكل شهر: مصروف «مستلزمات» (من المصروفات) مقابل استهلاك الخامات المسجّل من المخزون (تكلفة).
-- للمتابعة بس: مش بتتحسب تاني في الربح علشان ما يحصلش حساب مرتين. قراءة بس.
create or replace function public.materials_vs_supplies(p_months int default 6)
returns table(month date, supplies numeric, consumed numeric)
language plpgsql stable security definer
set search_path to 'public'
as $fn$
declare i int; d1 date; m date; v_tz text := my_tz();
begin
  if not (is_mgr() or has_perm('view_reports')) then raise exception 'غير مصرح'; end if;
  m := date_trunc('month', (now() at time zone v_tz))::date;
  for i in 0 .. greatest(least(coalesce(p_months, 6), 24), 1) - 1 loop
    d1 := (m - make_interval(months => i))::date;
    return query select d1,
      coalesce((select sum(e.amount) from expenses e where e.category = 'مستلزمات' and e.spent_on >= d1 and e.spent_on < (d1 + interval '1 month')::date), 0),
      coalesce((select sum(-mm.qty * mt.cost) from material_movements mm join materials mt on mt.id = mm.material_id
                 where mm.reason not in ('initial', 'restock')
                   and mm.created_at >= d1::timestamp at time zone v_tz and mm.created_at < (d1 + interval '1 month')::date::timestamp at time zone v_tz), 0);
  end loop;
end $fn$;
revoke all on function public.materials_vs_supplies(int) from public, anon;
grant execute on function public.materials_vs_supplies(int) to authenticated;
