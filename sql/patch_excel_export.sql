-- تصدير التقارير للإكسيل (للمالك فقط).
-- export_report: بترجّع بيانات الفترة جاهزة لملف الإكسيل (6 جداول). بتشتغل بطريقتين:
--   1) المالك مسجّل دخول في التطبيق (زرار "تصدير إكسيل")
--   2) مفتاح تصدير سري (قراءة فقط) المالك بيعمله ويقدر يلغيه، للربط من الكمبيوتر
-- مفيش أي مفتاح سري (Service Role) بيتحط في الملف. المفتاح بيتخزن مشفّر (SHA-256).
create table if not exists public.export_tokens (
  id bigint generated always as identity primary key,
  label text not null,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
alter table public.export_tokens enable row level security;
revoke all on public.export_tokens from anon, authenticated;

create or replace function public.owner_make_export_token(p_label text default 'إكسيل')
returns text language plpgsql security definer set search_path = public, extensions as $$
declare t text;
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  t := 'xl_' || encode(extensions.gen_random_bytes(24), 'hex');
  insert into export_tokens(label, token_hash) values (coalesce(nullif(btrim(p_label),''),'إكسيل'), encode(extensions.digest(t, 'sha256'), 'hex'));
  return t;   -- بيظهر مرة واحدة بس
end $$;

create or replace function public.owner_export_tokens()
returns table(id bigint, label text, created_at timestamptz, last_used_at timestamptz, revoked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  return query select t.id, t.label, t.created_at, t.last_used_at, t.revoked_at from export_tokens t order by t.id desc;
end $$;

create or replace function public.owner_revoke_export_token(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  update export_tokens set revoked_at = now() where id = p_id and revoked_at is null;
end $$;

create or replace function public.export_report(p_token text, p_from date, p_to date)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare
  tz text := my_tz(); cap constant int := 1000;
  tf timestamptz; tt timestamptz;
  v_sales jsonb; v_bar jsonb; v_att jsonb; v_inv jsonb; v_svc jsonb; v_cash jsonb;
  n_sales int; n_bar int; n_att int; n_inv int; n_svc int; n_cash int;
  h text;
begin
  if is_owner() then null;
  else
    if p_token is null or p_token = '' then raise exception 'غير مصرح'; end if;
    h := encode(extensions.digest(p_token, 'sha256'), 'hex');
    update export_tokens set last_used_at = now() where token_hash = h and revoked_at is null;
    if not found then raise exception 'غير مصرح'; end if;
  end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'الفترة غير صحيحة'; end if;
  if p_to - p_from > 366 then raise exception 'الفترة أطول من سنة'; end if;
  tf := p_from::timestamp at time zone tz; tt := (p_to + 1)::timestamp at time zone tz;

  -- المبيعات والأرباح: [رقم, تاريخ, عميل, حلاق, حالة, دفع, مبيعات, تكلفة منتجات, مصروفات, عمولات, رواتب/مكافآت, ملاحظات]
  -- نفس معادلة الربح في "التقرير الشامل": مبيعات − تكلفة منتجات − مصروفات − عمولات − (راتب ثابت + مكافآت − خصومات)
  with r as (
    select 1 g, i.created_at ts,
      jsonb_build_array(i.no, to_char(i.created_at at time zone tz, 'YYYY-MM-DD HH24:MI'), coalesce(c.name, 'عميل عابر'), b.full_name, 'مدفوعة', case i.payment_method when 'cash' then 'كاش' when 'card' then 'كارت' when 'wallet' then 'محفظة' else i.payment_method end, i.total,
        coalesce((select sum(p.cost * ii.qty) from invoice_items ii join products p on p.id = ii.item_id where ii.invoice_id = i.id and ii.item_type = 'product'), 0),
        null,
        case when b.role::text = 'assistant' then 0 else round((i.total - coalesce((select sum(x.assistant_cut) from invoice_items x where x.invoice_id = i.id), 0)) * coalesce(b.commission_pct, 0) / 100, 2) end,
        null, null) j
      from invoices i left join customers c on c.id = i.customer_id left join profiles b on b.id = i.barber_id
     where i.created_at >= tf and i.created_at < tt
    union all
    select 2, e.spent_on::timestamp at time zone tz,
      jsonb_build_array(null, e.spent_on::text, null, null, 'مصروف', null, null, null, e.amount, null, null, e.category || coalesce(' — ' || nullif(e.note,''), ''))
      from expenses e where e.spent_on >= p_from and e.spent_on <= p_to
    union all
    select 3, tt - interval '1 second',
      jsonb_build_array(null, p_to::text, null, pr.full_name, 'راتب ثابت (استحقاق الفترة)', null, null, null, null, null, round(salary_part_for(pr.id, pr.salary, tf, tt), 2), null)
      from profiles pr where pr.role::text <> 'owner' and coalesce(pr.salary, 0) > 0 and round(salary_part_for(pr.id, pr.salary, tf, tt), 2) > 0
    union all
    select 4, t.created_at,
      jsonb_build_array(null, to_char(t.created_at at time zone tz, 'YYYY-MM-DD HH24:MI'), null, pr.full_name, case when t.kind = 'bonus' and coalesce(t.note,'') like 'أجر يوم%' then 'أجر يوم' when t.kind = 'bonus' then 'مكافأة' else 'خصم' end, null, null, null, null, null,
        case t.kind when 'bonus' then t.amount else -t.amount end, t.note)
      from staff_transactions t join profiles pr on pr.id = t.staff_id
     where t.kind in ('bonus','deduction') and t.created_at >= tf and t.created_at < tt and pr.role::text <> 'owner'
  ), o as (select j, row_number() over (order by ts, g) rn from r)
  select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_sales, n_sales from o;

  -- حسابات الحلاقين: [تاريخ, معرّف, اسم, إيراد خدمات, عمولة, راتب/مكافأة, سلفة/سحب, خصم, (معادلة), نوع, مرجع, ملاحظات]
  with r as (
    select 1 g, i.created_at::date d0, i.barber_id sid,
      jsonb_build_array((i.created_at at time zone tz)::date::text, i.barber_id::text, b.full_name, sum(i.total),
        case when b.role::text = 'assistant' then 0 else round(sum(i.total - coalesce((select sum(x.assistant_cut) from invoice_items x where x.invoice_id = i.id), 0)) * coalesce(b.commission_pct, 0) / 100, 2) end,
        null, null, null, null, 'خدمات', count(*)::text || ' فاتورة', null) j,
      (i.created_at at time zone tz)::date d
      from invoices i join profiles b on b.id = i.barber_id
     where i.created_at >= tf and i.created_at < tt group by (i.created_at at time zone tz)::date, i.barber_id, b.full_name, b.role, b.commission_pct, i.created_at::date
    union all
    select 2, null, pr.id,
      jsonb_build_array(p_to::text, pr.id::text, pr.full_name, null, null, round(salary_part_for(pr.id, pr.salary, tf, tt), 2), null, null, null, 'راتب ثابت (استحقاق الفترة)', null, null), p_to
      from profiles pr where pr.role::text <> 'owner' and coalesce(pr.salary, 0) > 0 and round(salary_part_for(pr.id, pr.salary, tf, tt), 2) > 0
    union all
    select 3, null, t.staff_id,
      jsonb_build_array((t.created_at at time zone tz)::date::text, t.staff_id::text, pr.full_name,
        null, null, case when t.kind = 'bonus' then t.amount end, case when t.kind = 'advance' then t.amount end, case when t.kind = 'deduction' then t.amount end, null,
        case when t.kind = 'bonus' and coalesce(t.note,'') like 'أجر يوم%' then 'أجر يوم' when t.kind = 'bonus' then 'مكافأة' when t.kind = 'advance' then 'سلفة' else 'خصم' end, t.id::text, t.note), (t.created_at at time zone tz)::date
      from staff_transactions t join profiles pr on pr.id = t.staff_id
     where t.created_at >= tf and t.created_at < tt and pr.role::text <> 'owner'
    union all
    select 4, null, s.staff_id,
      jsonb_build_array(s.paid_on::text, s.staff_id::text, pr.full_name, null, null, null, s.amount, null, null, 'مرتب مدفوع', s.id::text, s.note), s.paid_on
      from salary_payments s join profiles pr on pr.id = s.staff_id where s.paid_on >= p_from and s.paid_on <= p_to
  ), o as (select j, row_number() over (order by d, g) rn from r)
  select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_bar, n_bar from o;

  -- الحضور: [تاريخ, معرّف, اسم, وردية من, وردية إلى, حضور, انصراف, دقائق تأخير, حالة, ملاحظات]
  with o as (
    select jsonb_build_array((a.check_in at time zone tz)::date::text, a.staff_id::text, pr.full_name,
        to_char(sh.start_time, 'HH24:MI'), to_char(sh.end_time, 'HH24:MI'),
        to_char(a.check_in at time zone tz, 'HH24:MI'), to_char(a.check_out at time zone tz, 'HH24:MI'),
        coalesce(a.late_min, 0), case when a.check_out is null then 'لم يسجل انصراف' else 'حاضر' end, a.note) j,
      row_number() over (order by a.check_in) rn
      from attendance a join profiles pr on pr.id = a.staff_id
      left join staff_shifts sh on sh.staff_id = a.staff_id and sh.weekday = extract(dow from (a.check_in at time zone tz))::int and not coalesce(sh.is_off, false)
     where a.check_in >= tf and a.check_in < tt
  ) select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_att, n_att from o;

  -- المخزون: [تاريخ, كود, اسم, نوع حركة, وارد, منصرف, (معادلة), تكلفة وحدة, (معادلة), مرجع, ملاحظات]
  with o as (
    select jsonb_build_array(to_char(m.created_at at time zone tz, 'YYYY-MM-DD HH24:MI'), m.product_id::text, p.name, m.reason,
        case when m.qty > 0 then m.qty end, case when m.qty < 0 then -m.qty end, null, p.cost, null, m.id::text, null) j,
      row_number() over (order by m.created_at, m.id) rn
      from stock_movements m join products p on p.id = m.product_id
     where m.created_at >= tf and m.created_at < tt
  ) select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_inv, n_inv from o;

  -- العملاء والخدمات: [رقم فاتورة, تاريخ, معرّف عميل, خدمة, حلاق, كمية, إيراد, حالة, ملاحظات]
  with o as (
    select jsonb_build_array(i.no, to_char(i.created_at at time zone tz, 'YYYY-MM-DD HH24:MI'), i.customer_id::text, ii.name, b.full_name, ii.qty, ii.qty * ii.unit_price, 'مدفوعة', null) j,
      row_number() over (order by i.created_at, ii.id) rn
      from invoice_items ii join invoices i on i.id = ii.invoice_id left join profiles b on b.id = i.barber_id
     where ii.item_type = 'service' and i.created_at >= tf and i.created_at < tt
  ) select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_svc, n_svc from o;

  -- الخزنة: [تاريخ, نقدي متوقع, نقدي فعلي, إضافات, سحوبات, (فرق), كارت, محافظ, تحويلات, ملاحظات]
  with d as (select gs::date as day from generate_series(p_from, p_to, interval '1 day') gs),
  f as (
    select d.day, day_figures(d.day) fg, cc.expected_cash, cc.counted_cash, cc.note, cc.opening cl_open,
           exists (select 1 from business_days b where b.day = d.day and b.closed_at is null) is_open
      from d left join cash_closings cc on cc.day = d.day
  ), o as (
    select jsonb_build_array(f.day::text,
        coalesce(f.expected_cash, expected_cash_of(f.fg, (f.fg->>'opening')::numeric)),
        f.counted_cash, (f.fg->>'moves_in')::numeric, (f.fg->>'moves_out')::numeric, null,
        (f.fg->>'card_sales')::numeric, (f.fg->>'wallet_sales')::numeric, null,
        case when f.counted_cash is not null then coalesce(f.note, 'مقفول بجرد') when f.is_open then 'اليوم مفتوح (لسه ما اتجردش)' else 'لم يُجرد' end) j,
      row_number() over (order by f.day) rn
      from f where f.counted_cash is not null or f.is_open or (f.fg->>'invoices')::int > 0 or (f.fg->>'moves_in')::numeric > 0 or (f.fg->>'moves_out')::numeric > 0
              or (f.fg->>'exp_cash')::numeric > 0 or (f.fg->>'adv_cash')::numeric > 0
  ) select coalesce(jsonb_agg(j order by rn) filter (where rn <= cap), '[]'::jsonb), count(*) into v_cash, n_cash from o;

  return jsonb_build_object(
    'meta', jsonb_build_object('from', p_from, 'to', p_to, 'generated_at', now(),
      'counts', jsonb_build_object('sales', n_sales, 'barbers', n_bar, 'attendance', n_att, 'inventory', n_inv, 'services', n_svc, 'cash', n_cash),
      'truncated', (greatest(n_sales, n_bar, n_att, n_inv, n_svc, n_cash) > cap)),
    'sales', v_sales, 'barbers', v_bar, 'attendance', v_att, 'inventory', v_inv, 'services', v_svc, 'cash', v_cash);
end $$;

revoke all on function public.owner_make_export_token(text), public.owner_export_tokens(), public.owner_revoke_export_token(bigint) from public, anon;
grant execute on function public.owner_make_export_token(text), public.owner_export_tokens(), public.owner_revoke_export_token(bigint) to authenticated;
revoke all on function public.export_report(text, date, date) from public;
grant execute on function public.export_report(text, date, date) to anon, authenticated;
