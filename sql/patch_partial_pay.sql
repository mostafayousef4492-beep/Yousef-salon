-- دفع جزء من المبلغ والباقي دين على الزبون.
--  • الفاتورة بتتسجل بالمدفوع بس (total = المدفوع) فالمبيعات والعمولة والدرج كلها على المدفوع؛ المتبقي في unpaid.
--  • الزبون ممكن يكون مسجّل أو لأ (اسم/رقم بتكتبه يدوي في debtor_name / debtor_phone).
--  • السداد (debt_collect) بيعمل فاتورة سداد بتاريخ اليوم، بنفس حلاق الفاتورة الأصلية، فالفلوس بتدخل الدرج
--    في يوم السداد والعمولة بتتحسب وقتها. فاتورة السداد مفيهاش بنود ومابتدّيش نقاط ولا زيارات.
-- آمن للتكرار. لا يمس أي فاتورة موجودة (unpaid = 0 افتراضيًا).
begin;
alter table public.invoices add column if not exists unpaid numeric(10,2) not null default 0;
alter table public.invoices add column if not exists debtor_name text;
alter table public.invoices add column if not exists debtor_phone text;
alter table public.invoices add column if not exists settles_invoice bigint references public.invoices(id) on delete set null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoices_unpaid_check') then
    alter table public.invoices add constraint invoices_unpaid_check check (unpaid >= 0);
  end if;
end $$;
create index if not exists invoices_settles_idx on public.invoices(settles_invoice) where settles_invoice is not null;
create index if not exists invoices_unpaid_idx on public.invoices(customer_id) where unpaid > 0;

-- تسجيل الباقي كدين على فاتورة لسه متحاسبة (بيتنادى بعد pos_checkout زي invoice_set_paid)
create or replace function public.invoice_set_unpaid(p_invoice bigint, p_unpaid numeric, p_name text default null, p_phone text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare i invoices; v_nm text := nullif(btrim(coalesce(p_name, '')), ''); v_ph text := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), '');
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found then raise exception 'الفاتورة مش موجودة'; end if;
  if not is_mgr() and (i.created_at < now() - interval '15 minutes' or i.cashier_id is distinct from auth.uid()) then
    raise exception 'تسجيل الدين للمدير بعد ما الفاتورة تعدي 15 دقيقة'; end if;
  if i.settles_invoice is not null then raise exception 'دي فاتورة سداد'; end if;
  if i.unpaid > 0 then raise exception 'الفاتورة دي عليها دين متسجل بالفعل'; end if;
  if i.extra_paid > 0 then raise exception 'الفاتورة دي فيها زيادة مدفوعة — مينفعش يتسجل عليها دين'; end if;
  if p_unpaid is null or p_unpaid <= 0 then raise exception 'مبلغ الباقي لازم يكون أكبر من صفر'; end if;
  if p_unpaid >= i.total then raise exception 'الباقي (%) لازم يكون أقل من إجمالي الفاتورة (%) — لازم الزبون يدفع جزء على الأقل', p_unpaid, i.total; end if;
  if i.customer_id is null and v_nm is null then raise exception 'اكتب اسم الزبون اللي عليه الباقي'; end if;
  update invoices set total = total - p_unpaid, unpaid = p_unpaid, debtor_name = v_nm, debtor_phone = v_ph where id = p_invoice;
  return jsonb_build_object('paid', i.total - p_unpaid, 'unpaid', p_unpaid);
end $$;
revoke all on function public.invoice_set_unpaid(bigint, numeric, text, text) from public, anon;
grant execute on function public.invoice_set_unpaid(bigint, numeric, text, text) to authenticated;

-- الديون المفتوحة (متبقي > 0). p_customer لو عايز دين زبون معيّن.
create or replace function public.debts_list(p_customer bigint default null)
returns table(invoice_id bigint, no bigint, created_at timestamptz, customer_id bigint, name text, phone text, barber text,
              unpaid numeric, collected numeric, remaining numeric)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  return query
  select i.id, i.no, i.created_at, i.customer_id, coalesce(c.name, i.debtor_name, '—')::text,
         coalesce(c.phone, i.debtor_phone)::text, b.full_name::text, i.unpaid,
         coalesce(s.t, 0)::numeric, (i.unpaid - coalesce(s.t, 0))::numeric
    from invoices i
    left join customers c on c.id = i.customer_id
    left join profiles b on b.id = i.barber_id
    left join lateral (select sum(x.total) t from invoices x where x.settles_invoice = i.id) s on true
   where i.unpaid > 0 and i.unpaid - coalesce(s.t, 0) > 0.004
     and (p_customer is null or i.customer_id = p_customer)
   order by i.created_at;
end $$;
revoke all on function public.debts_list(bigint) from public, anon;
grant execute on function public.debts_list(bigint) to authenticated;

-- سداد (كامل أو جزء) من دين فاتورة. بترجّع رقم فاتورة السداد.
create or replace function public.debt_collect(p_invoice bigint, p_amount numeric, p_method text default 'cash')
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare i invoices; v_rem numeric; v_new bigint;
begin
  if not (is_mgr() or can_use_pos()) then raise exception 'غير مصرح'; end if;
  if p_method not in ('cash', 'card', 'wallet') then raise exception 'طريقة الدفع غير صحيحة'; end if;
  select * into i from invoices where id = p_invoice for update;
  if not found or i.unpaid <= 0 then raise exception 'مفيش دين على الفاتورة دي'; end if;
  select i.unpaid - coalesce(sum(x.total), 0) into v_rem from invoices x where x.settles_invoice = i.id;
  if p_amount is null or p_amount <= 0 then raise exception 'اكتب مبلغ السداد'; end if;
  if p_amount > v_rem + 0.004 then raise exception 'المبلغ (%) أكبر من المتبقي (%)', p_amount, v_rem; end if;
  insert into invoices(customer_id, barber_id, subtotal, discount, total, payment_method, settles_invoice, debtor_name, debtor_phone)
  values (i.customer_id, i.barber_id, round(p_amount, 2), 0, round(p_amount, 2), p_method, i.id, i.debtor_name, i.debtor_phone)
  returning id into v_new;
  return v_new;
end $$;
revoke all on function public.debt_collect(bigint, numeric, text) from public, anon;
grant execute on function public.debt_collect(bigint, numeric, text) to authenticated;

-- فاتورة السداد مش "حلاقة": ماتحسبش في تقدّم الحلاق
create or replace function public.p13_invoice_after() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  begin
    if NEW.barber_id is not null and NEW.settles_invoice is null then perform p13_progress(NEW.barber_id, true); end if;
  exception when others then
    raise warning 'p13 invoice awards: %', sqlerrm;
  end;
  return NEW;
end $$;
commit;
