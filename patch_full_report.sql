-- التقرير الشامل: شغل المحل، المصاريف (بنود)، صافي الربح، وحساب كل موظف. للمالك/المدير بس.
-- نفس معادلة الربح في report_data بالظبط، فالأرقام بتطابق «الملخص».
create or replace function public.full_report(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tz text := my_tz(); d1 date; d2 date; v_rev numeric; v_n int; v_cogs numeric; v_exp numeric; v_staff jsonb; v_cost numeric; v_comm numeric; v_sal numeric; v_bon numeric; v_ded numeric;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'الفترة غير صحيحة'; end if;
  d1 := (p_from at time zone tz)::date; d2 := (p_to at time zone tz)::date;
  select coalesce(sum(total),0), count(*) into v_rev, v_n from invoices where created_at >= p_from and created_at < p_to;
  select coalesce(sum(p.cost * ii.qty),0) into v_cogs from invoice_items ii join invoices i on i.id = ii.invoice_id join products p on p.id = ii.item_id
    where ii.item_type = 'product' and i.created_at >= p_from and i.created_at < p_to;
  select coalesce(sum(amount),0) into v_exp from expenses where spent_on >= d1 and spent_on < d2;

  with s as (
    select pr.id, pr.full_name n, pr.role::text r,
      coalesce(sales.sales,0) sales, coalesce(sales.cuts,0) cuts,
      case when pr.role = 'assistant' then 0 else round(coalesce(sales.net,0) * coalesce(pr.commission_pct,0) / 100, 2) end comm,
      case when pr.salary > 0 then round(salary_part(pr.salary, p_from, p_to), 2) else 0 end sal,
      coalesce(t.bon,0) bon, coalesce(t.ded,0) ded, coalesce(t.adv,0) adv,
      coalesce((select sum(sp.amount) from salary_payments sp where sp.staff_id = pr.id and sp.created_at >= p_from and sp.created_at < p_to),0) paid,
      coalesce((select (staff_statement(pr.id, null, now())->>'closing')::numeric),0) balance
    from profiles pr
    left join lateral (select sum(i.total) sales, count(*) cuts, sum(i.total - coalesce((select sum(x.assistant_cut) from invoice_items x where x.invoice_id = i.id),0)) net
                         from invoices i where i.barber_id = pr.id and i.created_at >= p_from and i.created_at < p_to) sales on true
    left join lateral (select sum(amount) filter (where kind='bonus') bon, sum(amount) filter (where kind='deduction') ded, sum(amount) filter (where kind='advance') adv
                         from staff_transactions where staff_id = pr.id and created_at >= p_from and created_at < p_to) t on true
    where pr.role <> 'owner'
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',n,'role',r,'sales',sales,'cuts',cuts,'commission',comm,'salary',sal,'bonus',bon,'deduction',ded,
           'advance',adv,'paid',paid,'balance',balance,'cost',comm + sal + bon - ded) order by sales desc, n),'[]'::jsonb),
         coalesce(sum(comm),0), coalesce(sum(sal),0), coalesce(sum(bon),0), coalesce(sum(ded),0), coalesce(sum(comm + sal + bon - ded),0)
    into v_staff, v_comm, v_sal, v_bon, v_ded, v_cost from s where sales > 0 or comm <> 0 or sal <> 0 or bon <> 0 or ded <> 0 or adv > 0 or paid > 0 or balance <> 0;

  return jsonb_build_object('revenue',v_rev,'invoices',v_n,'cogs',v_cogs,'expenses',v_exp,'staff_cost',v_cost,
    'commissions',v_comm,'salaries',v_sal,'bonuses',v_bon,'deductions',v_ded,
    'profit', v_rev - v_cogs - v_exp - v_cost, 'staff', v_staff,
    'expense_cats', (select coalesce(jsonb_agg(jsonb_build_object('c',c,'t',t,'n',n) order by t desc),'[]'::jsonb) from (select category c, sum(amount) t, count(*) n from expenses where spent_on >= d1 and spent_on < d2 group by 1) x),
    'by_pay', (select coalesce(jsonb_agg(jsonb_build_object('m',payment_method,'n',n,'t',t) order by t desc),'[]'::jsonb) from (select payment_method, count(*) n, sum(total) t from invoices where created_at >= p_from and created_at < p_to group by 1) x));
end $$;
revoke all on function public.full_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.full_report(timestamptz, timestamptz) to authenticated;
