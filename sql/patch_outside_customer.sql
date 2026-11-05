-- «خارج المحل» من تطبيق العميل + عمولة الحلاق على الخدمة بس (من غير مبلغ خارج المحل):
--  1) appointments.outside: العميل بيختار خارج المحل وقت الحجز، والكاشير بيلاقيه مختار.
--  2) set_ticket_outside(ticket, outside, phone): زي set_ticket_bundle (العميل أو الكاشير).
--  3) staff_summary + staff_cuts_list: العمولة بتتحسب على الإجمالي ناقص بند «خدمة خارج المحل» (المبلغ ده للمحل).
--     (staff_daily_due بيعتمد على staff_summary فبيتصلح معاه.) آمن للتكرار.
begin;
alter table public.appointments add column if not exists outside boolean not null default false;

create or replace function public.set_ticket_outside(p_id bigint, p_outside boolean, p_phone text default null)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments; ok boolean; staff boolean;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'التذكرة مش موجودة'; end if;
  staff := is_mgr() or has_perm('manage_appts') or can_use_pos();
  ok := staff or exists (select 1 from customers c where c.id = a.customer_id and (c.user_id = auth.uid()
          or (p_phone is not null and c.phone = regexp_replace(p_phone, '\D', '', 'g'))));
  if not ok then raise exception 'غير مصرح'; end if;
  if a.status::text not in ('upcoming', 'checked_in') and not (staff and a.status::text = 'in_service') then
    raise exception 'مينفعش تغيّر المكان دلوقتي'; end if;
  update appointments set outside = coalesce(p_outside, false) where id = p_id;
end $$;
revoke all on function public.set_ticket_outside(bigint, boolean, text) from public;
grant execute on function public.set_ticket_outside(bigint, boolean, text) to anon, authenticated;

do $$
declare d text; n text; old text := 'v_c := (v_s - v_ac) * coalesce(v_p,0) / 100;';
begin
  select pg_get_functiondef('public.staff_summary(uuid,timestamptz,timestamptz)'::regprocedure) into d;
  if position('خدمة خارج المحل' in d) > 0 then return; end if;
  if position(old in d) = 0 then raise exception 'staff_summary مختلفة عن المتوقع'; end if;
  n := replace(d, old, $n$v_c := (v_s - v_ac - coalesce((select sum(ii.unit_price * ii.qty) from invoice_items ii join invoices i on i.id = ii.invoice_id
        where i.barber_id = p_staff and i.created_at >= p_from and i.created_at < p_to and ii.item_type = 'service' and ii.item_id = 0 and ii.name = 'خدمة خارج المحل'), 0)) * coalesce(v_p,0) / 100;$n$);
  execute n;
end $$;

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
                else (i.total - coalesce((select sum(ii.assistant_cut) from invoice_items ii where ii.invoice_id = i.id), 0)
                              - coalesce((select sum(ii.unit_price * ii.qty) from invoice_items ii where ii.invoice_id = i.id and ii.item_type = 'service' and ii.item_id = 0 and ii.name = 'خدمة خارج المحل'), 0)) * v_pct / 100 end
      from invoices i left join customers c on c.id = i.customer_id
     where i.barber_id = p_staff and i.created_at >= p_from and i.created_at < p_to
     order by i.created_at desc limit 300;
end $$;
revoke all on function public.staff_cuts_list(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.staff_cuts_list(uuid, timestamptz, timestamptz) to authenticated;
commit;
