-- ============================================================================
-- (1) مشروب استاف: طريقة دفع جديدة 'staff' = قهوة طالعة. بتخصم من المخزون وبتتحسب تكلفة (cogs) في تقرير الكوفي،
--     لكن مفيش فلوس: إجمالي البيع 0 فمفيش أثر على الدرج ولا مبيعات اليوم ولا الأرباح غير التكلفة. مش بتتسجل على فاتورة ولا آجل.
-- (2) موظف الكوفي (مش المدير) بيشوف مبيعاته ومصروفاته وسحوباته من وقت حضوره لحد انصرافه (آخر وردية)، مش كل اليوم.
--     المدير والمالك بيشوفوا يوم العمل كله زي الأول. مفيش حضور = قايمة فاضية (البيع نفسه مش بيتمنع).
-- بيتشغّل بعد patch_cafe_staff.sql. آمن للتكرار. مفيش حذف لأي بيانات.
-- ============================================================================
do $$
begin
  if to_regprocedure('public.cafe_staff_day()') is null then raise exception 'شغّل patch_cafe_staff.sql الأول'; end if;
end $$;

do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.cafe_sales'::regclass and contype = 'c' and conname <> 'cafe_sales_method_chk'
              and pg_get_constraintdef(oid) like '%payment_method%' loop
    execute format('alter table cafe_sales drop constraint %I', c.conname);
  end loop;
  alter table cafe_sales drop constraint if exists cafe_sales_method_chk;
  alter table cafe_sales add constraint cafe_sales_method_chk
    check (payment_method in ('cash','card','wallet','credit','staff') and ((payment_method = 'credit') = (debtor_id is not null)));
end $$;

-- وردية الموظف: من آخر حضور له (خلال 36 ساعة) لحد انصرافه (أو دلوقتي لو لسه حاضر). مفيش حضور = وردية فاضية.
create or replace function p34_my_shift(out v_from timestamptz, out v_to timestamptz, out v_open boolean)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  select a.check_in, coalesce(a.check_out, now()), a.check_out is null into v_from, v_to, v_open
    from attendance a where a.staff_id = auth.uid() and a.check_in > now() - interval '36 hours' order by a.check_in desc limit 1;
  if v_from is null then v_from := 'infinity'; v_to := '-infinity'; v_open := false; end if;
end $$;
revoke execute on function public.p34_my_shift() from public, anon;
grant execute on function public.p34_my_shift() to authenticated;

create or replace function cafe_sell(p_items jsonb, p_method text, p_invoice bigint default null, p_note text default null, p_debtor bigint default null)
returns bigint language plpgsql security definer set search_path to 'public' as $$
declare v_id bigint; it jsonb; v_qty int; r cafe_products; v_total numeric := 0; v_method text := p_method; v_inv invoices; v_deb_id bigint;
begin
  if not can_use_cafe() then raise exception 'غير مصرح'; end if;
  if p_method = 'staff' and (p_invoice is not null or p_debtor is not null) then raise exception 'مشروب الاستاف مش بيتسجل على فاتورة ولا آجل'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'اختار منتج واحد على الأقل'; end if;
  if p_invoice is not null then
    select * into v_inv from invoices where id = p_invoice;
    if not found then raise exception 'الفاتورة مش موجودة'; end if;
    v_method := v_inv.payment_method;                    -- المشروب بيتدفع مع فاتورة الصالون بنفس الطريقة
  end if;
  if v_method = 'staff' then
    null;                                                -- مشروب استاف: مفيش دفع ومفيش فلوس
  elsif v_method = 'credit' then
    if p_invoice is not null then raise exception 'الآجل مش متاح مع فاتورة الصالون'; end if;
    if p_debtor is null then raise exception 'اختار العميل اللي هيتسجّل عليه الآجل'; end if;
    select id into v_deb_id from cafe_customers where id = p_debtor and active for update;
    if not found then raise exception 'العميل مش موجود'; end if;
  else
    perform cafe_pay_ok(v_method);
  end if;
  insert into cafe_sales(invoice_id, payment_method, total, note, created_by, debtor_id)
    values (p_invoice, v_method, 0, nullif(btrim(coalesce(p_note,'')),''), auth.uid(), v_deb_id) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    v_qty := coalesce((it->>'qty')::int, 1);
    if v_qty < 1 or v_qty > 99 then raise exception 'كمية غير صحيحة'; end if;
    select * into r from cafe_products where id = (it->>'id')::bigint and active for update;
    if not found then raise exception 'منتج غير موجود أو متوقف'; end if;
    if r.track_stock then
      if r.stock < v_qty then raise exception 'المخزون مش كفاية: %', r.name; end if;
      update cafe_products set stock = stock - v_qty where id = r.id;
      insert into cafe_stock_movements(product_id, qty, reason, created_by) values (r.id, -v_qty, 'sale', auth.uid());
    end if;
    insert into cafe_sale_items(sale_id, product_id, name, qty, unit_price, unit_cost) values (v_id, r.id, r.name, v_qty, case when v_method = 'staff' then 0 else r.price end, r.cost);
    v_total := v_total + (case when v_method = 'staff' then 0 else r.price end) * v_qty;
  end loop;
  update cafe_sales set total = v_total where id = v_id;
  return v_id;
end $$;

create or replace function cafe_recent_sales(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_mgr boolean := is_mgr(); v_from timestamptz; v_to timestamptz; v_open boolean;
begin
  if not can_use_cafe() then raise exception 'غير مصرح'; end if;
  if not v_mgr then select * into v_from, v_to, v_open from p34_my_shift(); end if;
  return coalesce((select jsonb_agg(q.x order by q.at desc) from (
    select jsonb_build_object('id', s.id, 'at', s.created_at, 'kind', case when s.invoice_id is null then 'street' else 'salon' end,
      'invoice_no', i.no, 'method', s.payment_method, 'total', s.total, 'status', s.status, 'note', s.note, 'void_reason', s.void_reason,
      'debtor', c.name,
      'can_void', s.status = 'paid' and (v_mgr or (s.created_by = auth.uid() and s.invoice_id is null and s.created_at > now() - interval '30 minutes')),
      'items', coalesce((select jsonb_agg(jsonb_build_object('name', it.name, 'qty', it.qty, 'price', it.unit_price) order by it.id)
                           from cafe_sale_items it where it.sale_id = s.id), '[]'::jsonb)) x, s.created_at at
      from cafe_sales s left join invoices i on i.id = s.invoice_id left join cafe_customers c on c.id = s.debtor_id
     where v_mgr or (s.created_by = auth.uid() and s.created_at between v_from and v_to)
     order by s.created_at desc limit greatest(least(coalesce(p_limit, 30), 200), 1)) q), '[]'::jsonb);
end $$;

create or replace function cafe_staff_day() returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_day date := biz_today(); v_tz text := my_tz(); v_mgr boolean := is_mgr(); v_me uuid := auth.uid(); v_own boolean := is_owner(); v_from timestamptz; v_to timestamptz; v_open boolean;
begin
  if not can_use_cafe() then raise exception 'غير مصرح'; end if;
  if not v_mgr then select * into v_from, v_to, v_open from p34_my_shift(); end if;
  return jsonb_build_object('day', v_day, 'scope', case when v_mgr then 'all' else 'mine' end,
    'shift', case when v_mgr then null else jsonb_build_object('from', case when v_from = 'infinity' then null else v_from end, 'to', case when v_from = 'infinity' then null else v_to end, 'open', v_open) end,
    'sales', (select jsonb_build_object('orders', count(*) filter (where s.payment_method <> 'staff'), 'staff_drinks', count(*) filter (where s.payment_method = 'staff'),
                'cash',   coalesce(sum(s.total) filter (where s.payment_method = 'cash'), 0),
                'card',   coalesce(sum(s.total) filter (where s.payment_method = 'card'), 0),
                'wallet', coalesce(sum(s.total) filter (where s.payment_method = 'wallet'), 0),
                'credit', coalesce(sum(s.total) filter (where s.payment_method = 'credit'), 0))
                from cafe_sales s where s.status = 'paid' and (case when v_mgr then p24b_in_day(s.created_at, v_day, v_tz) else (s.created_by = v_me and s.created_at between v_from and v_to) end)),
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'amount', e.amount, 'category', e.category, 'note', e.note, 'at', e.created_at,
                  'can_void', v_own or (e.created_by = v_me and e.created_at > now() - interval '30 minutes')) order by e.id desc)
                from cafe_expenses e where e.purchase_id is null and (case when v_mgr then e.spent_on = v_day else (e.created_by = v_me and e.created_at between v_from and v_to) end)), '[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'amount', w.amount, 'kind', w.kind, 'note', w.note, 'at', w.created_at,
                  'can_void', v_own or (w.created_by = v_me and w.created_at > now() - interval '30 minutes')) order by w.id desc)
                from cafe_withdrawals w where w.status = 'ok' and (case when v_mgr then p24b_in_day(w.created_at, v_day, v_tz) else (w.created_by = v_me and w.created_at between v_from and v_to) end)), '[]'::jsonb),
    'collections', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'amount', p.amount, 'debtor', c.name, 'note', p.note, 'at', p.created_at,
                  'can_void', v_own or (p.created_by = v_me and p.created_at > now() - interval '30 minutes')) order by p.id desc)
                from cafe_debt_payments p join cafe_customers c on c.id = p.debtor_id
               where p.status = 'paid' and (case when v_mgr then p24b_in_day(p.created_at, v_day, v_tz) else (p.created_by = v_me and p.created_at between v_from and v_to) end)), '[]'::jsonb));
end $$;

create or replace function cafe_report(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare v_tz text := my_tz(); r jsonb;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'الفترة غير صحيحة'; end if;
  with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
  sd as (
    select s.id, s.invoice_id, s.payment_method, s.total, dd.day
      from cafe_sales s
      cross join lateral (select d.day from days d where p24b_in_day(s.created_at, d.day, v_tz) limit 1) dd
     where s.status = 'paid'
  ),
  it as (select i.sale_id, i.name, i.qty, i.unit_price, i.unit_cost from cafe_sale_items i where i.sale_id in (select id from sd)),
  ex as (select e.spent_on, e.category, e.amount from cafe_expenses e where e.spent_on between p_from and p_to),
  pu as (select p.bought_on, p.total, p.kind from cafe_purchases p where p.bought_on between p_from and p_to),
  dp as (select p.amount, dd.day from cafe_debt_payments p
           cross join lateral (select d.day from days d where p24b_in_day(p.created_at, d.day, v_tz) limit 1) dd where p.status = 'paid'),
  wd as (select w.kind, w.amount, dd.day from cafe_withdrawals w
           cross join lateral (select d.day from days d where p24b_in_day(w.created_at, d.day, v_tz) limit 1) dd where w.status = 'ok')
  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    'sales',        (select coalesce(sum(total),0) from sd),
    'salon_sales',  (select coalesce(sum(total),0) from sd where invoice_id is not null),
    'street_sales', (select coalesce(sum(total),0) from sd where invoice_id is null),
    'orders',       (select count(*) from sd where payment_method <> 'staff'),
    'staff_drinks', jsonb_build_object('orders', (select count(*) from sd where payment_method = 'staff'),
                      'qty',  (select coalesce(sum(i.qty),0) from it i join sd on sd.id = i.sale_id where sd.payment_method = 'staff'),
                      'cost', (select coalesce(sum(i.qty * i.unit_cost),0) from it i join sd on sd.id = i.sale_id where sd.payment_method = 'staff')),
    'cogs',         (select coalesce(sum(qty * unit_cost),0) from it),
    'purchases',    (select coalesce(sum(total),0) from pu),
    'expenses',     (select coalesce(sum(amount),0) from ex),
    'net_profit',   (select coalesce(sum(total),0) from sd) - (select coalesce(sum(qty * unit_cost),0) from it) - (select coalesce(sum(amount),0) from ex),
    'by_method',    jsonb_build_object(
                      'cash',   (select coalesce(sum(total),0) from sd where payment_method = 'cash'),
                      'card',   (select coalesce(sum(total),0) from sd where payment_method = 'card'),
                      'wallet', (select coalesce(sum(total),0) from sd where payment_method = 'wallet'),
                      'credit', (select coalesce(sum(total),0) from sd where payment_method = 'credit')),
    'credit_sales',   (select coalesce(sum(total),0) from sd where payment_method = 'credit'),
    'debt_collected', (select coalesce(sum(amount),0) from dp),
    'withdrawals',    (select coalesce(sum(amount),0) from wd),
    'withdrawals_by_kind', coalesce((select jsonb_agg(jsonb_build_object('kind', kind, 'amount', a) order by a desc)
                       from (select kind, sum(amount) a from wd group by kind) t), '[]'::jsonb),
    'outstanding_debt', (select coalesce(sum(b), 0) from (select cafe_debtor_balance(c.id) b from cafe_customers c) z where b > 0),
    'top_debtors', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'balance', b) order by b desc)
                       from (select c.id, c.name, cafe_debtor_balance(c.id) b from cafe_customers c) z where b > 0), '[]'::jsonb),
    'top', coalesce((select jsonb_agg(jsonb_build_object('name', n, 'qty', q, 'revenue', rev) order by q desc, rev desc)
                       from (select name n, sum(qty) q, sum(qty * unit_price) rev from it where sale_id not in (select id from sd where payment_method = 'staff') group by name order by sum(qty) desc, sum(qty * unit_price) desc limit 10) t), '[]'::jsonb),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d.day,
                         'sales', (select coalesce(sum(total),0) from sd where sd.day = d.day),
                         'orders', (select count(*) from sd where sd.day = d.day and sd.payment_method <> 'staff'),
                         'cogs', (select coalesce(sum(i2.qty * i2.unit_cost),0) from it i2 join sd on sd.id = i2.sale_id where sd.day = d.day),
                         'expenses', (select coalesce(sum(amount),0) from ex where ex.spent_on = d.day),
                         'purchases', (select coalesce(sum(total),0) from pu where pu.bought_on = d.day)) order by d.day) from days d), '[]'::jsonb),
    'expenses_by_category', coalesce((select jsonb_agg(jsonb_build_object('category', category, 'amount', a) order by a desc)
                       from (select category, sum(amount) a from ex group by category) t), '[]'::jsonb),
    'low_stock', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'stock', stock, 'min', min_stock) order by name)
                       from cafe_products where active and track_stock and stock <= min_stock), '[]'::jsonb)
  ) into r;
  return r;
end $$;
