-- قايمة زباين الحلاق في فترة: كل فاتورة (العميل، الخدمات، المبلغ، العمولة). الحلاق نفسه أو المدير بس.
-- نفس صلاحيات staff_summary: المبلغ بيتخفي لو الحلاق مالوش view_own_sales، والعمولة لو مالوش view_own_commission.
-- العمولة = (إجمالي الفاتورة − أجر المساعدين) × نسبة الحلاق / 100. آمن للتكرار.
create or replace function public.staff_cuts_list(p_staff uuid, p_from timestamptz, p_to timestamptz)
returns table(invoice_id bigint, at timestamptz, customer text, services text, total numeric, commission numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_pct numeric; v_self boolean;
begin
  if not (auth.uid() = p_staff or is_mgr()) then raise exception 'غير مصرح'; end if;
  v_self := auth.uid() = p_staff and not is_mgr();
  select coalesce(pr.commission_pct, 0) into v_pct from profiles pr where pr.id = p_staff;
  return query
    select i.id, i.created_at, coalesce(c.name, 'عميل عابر')::text,
           coalesce((select string_agg(ii.name, ' + ' order by ii.id) from invoice_items ii where ii.invoice_id = i.id and ii.item_type = 'service'), '')::text,
           case when v_self and not has_perm('view_own_sales') then null else i.total end,
           case when v_self and not has_perm('view_own_commission') then null
                else (i.total - coalesce((select sum(ii.assistant_cut) from invoice_items ii where ii.invoice_id = i.id), 0)) * v_pct / 100 end
      from invoices i left join customers c on c.id = i.customer_id
     where i.barber_id = p_staff and i.created_at >= p_from and i.created_at < p_to
     order by i.created_at desc limit 300;
end $$;
revoke all on function public.staff_cuts_list(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.staff_cuts_list(uuid, timestamptz, timestamptz) to authenticated;
