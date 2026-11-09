-- مساعد الإدارة الذكي: دوال تحليل للقراءة فقط (مالك/مدير بس).
-- • كل دالة security definer بس بتبدأ بفحص ai_admin_ok() → الكاشير/الحلاق/العميل بيتمنعوا.
-- • مفيش كتابة ولا تعديل في أي دالة هنا (stable). الدالة اللي بتكتب الوحيدة هي assistant_hit (patch_assistant.sql).
-- • p_names=false (الافتراضي، ودي اللي بتناديها الـ Edge Function) = مفيش أسماء عملاء ولا تليفونات ولا ملاحظات حرة،
--   فمفيش بيانات شخصية بتروح لمزود الذكاء الاصطناعي. واجهة المدير بتنادي بـ p_names=true عشان تفتح التفاصيل بالأسماء.
-- • مفتاح assistant_admin_manager (app_settings، افتراضي true): false = المساعد للمالك بس.
-- • حد الأسئلة اليومي للإدارة: assistant_limit_admin (افتراضي 60) — بيتعمل في assistant_hit (تحديث تحت).
-- • الأرقام بتستخدم نفس مصادر وصيغ التقارير الحالية (full_report) فمتتعارضش معاها.
-- آمن للتكرار. مفيش بيانات بتتغير.

create or replace function public.ai_admin_ok() returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
declare v_role text; v_set text;
begin
  select p.role::text into v_role from profiles p where p.id = auth.uid();
  if v_role = 'owner' then return true; end if;
  if v_role = 'manager' then
    select trim(both '"' from value::text) into v_set from app_settings where key = 'assistant_admin_manager';
    return coalesce(v_set, 'true') not in ('false', '0', 'off');
  end if;
  return false;
end $$;
revoke all on function public.ai_admin_ok() from public, anon;
grant execute on function public.ai_admin_ok() to authenticated;

create or replace function public.ai__chk(p_from timestamptz, p_to timestamptz) returns void
language plpgsql stable set search_path to 'public' as $$
begin
  if not ai_admin_ok() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'الفترة غير صحيحة'; end if;
  if p_to - p_from > interval '400 days' then raise exception 'الفترة أطول من 400 يوم'; end if;
end $$;
revoke all on function public.ai__chk(timestamptz, timestamptz) from public, anon;
grant execute on function public.ai__chk(timestamptz, timestamptz) to authenticated;

-- نظرة عامة: نفس full_report + متوسط الفاتورة + المتبقي (الديون)
create or replace function public.ai_overview(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare f jsonb; v_unpaid numeric; v_debt numeric; v_settle numeric; v_n int; v_rev numeric;
begin
  perform ai__chk(p_from, p_to);
  f := full_report(p_from, p_to);
  v_rev := (f->>'revenue')::numeric; v_n := (f->>'invoices')::int;
  select coalesce(sum(unpaid), 0) into v_unpaid from invoices where created_at >= p_from and created_at < p_to;
  select coalesce(sum(unpaid), 0) into v_debt from invoices where unpaid > 0;
  return f || jsonb_build_object(
    'avg_invoice', case when v_n > 0 then round(v_rev / v_n, 2) else null end,
    'unpaid_created_in_range', v_unpaid,
    'outstanding_debt_total_now', v_debt);
end $$;

-- ترتيب الخدمات/المنتجات حسب الطلب. الإيراد = السعر × الكمية قبل خصم الفاتورة.
create or replace function public.ai_items_rank(p_from timestamptz, p_to timestamptz, p_type text default 'service', p_limit int default 10)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r jsonb;
begin
  perform ai__chk(p_from, p_to);
  if p_type not in ('service', 'product') then raise exception 'النوع service أو product'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', n, 'qty', q, 'revenue', rv) order by q desc, rv desc), '[]'::jsonb) into r
    from (select ii.name n, sum(ii.qty) q, sum(ii.qty * ii.unit_price) rv
            from invoice_items ii join invoices i on i.id = ii.invoice_id
           where ii.item_type = p_type and i.created_at >= p_from and i.created_at < p_to
           group by ii.name order by sum(ii.qty) desc, sum(ii.qty * ii.unit_price) desc
           limit least(greatest(coalesce(p_limit, 10), 1), 50)) x;
  return jsonb_build_object('type', p_type, 'items', r,
    'total_qty', (select coalesce(sum(ii.qty), 0) from invoice_items ii join invoices i on i.id = ii.invoice_id where ii.item_type = p_type and i.created_at >= p_from and i.created_at < p_to));
end $$;

-- السلسلة اليومية (بتوقيت الصالون)
create or replace function public.ai_daily_series(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); r jsonb;
begin
  perform ai__chk(p_from, p_to);
  select coalesce(jsonb_agg(jsonb_build_object('day', d, 'revenue', rv, 'invoices', n) order by d), '[]'::jsonb) into r
    from (select (created_at at time zone tz)::date d, sum(total) rv, count(*) n
            from invoices where created_at >= p_from and created_at < p_to group by 1) x;
  return jsonb_build_object('days', r);
end $$;

-- المصروفات: بالبند + أكبر المصروفات. الملاحظات الحرة مش بترجع إلا لو p_names=true.
create or replace function public.ai_expenses(p_from timestamptz, p_to timestamptz, p_names boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); d1 date; d2 date;
begin
  perform ai__chk(p_from, p_to);
  d1 := (p_from at time zone tz)::date; d2 := (p_to at time zone tz)::date;
  return jsonb_build_object(
    'total', (select coalesce(sum(amount), 0) from expenses where spent_on >= d1 and spent_on < d2),
    'by_category', (select coalesce(jsonb_agg(jsonb_build_object('category', c, 'total', t, 'count', n) order by t desc), '[]'::jsonb)
                      from (select category c, sum(amount) t, count(*) n from expenses where spent_on >= d1 and spent_on < d2 group by 1) x),
    'largest', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'date', spent_on, 'category', category, 'amount', amount, 'purchase_id', purchase_id)
                  || case when p_names then jsonb_build_object('note', note) else '{}'::jsonb end order by amount desc), '[]'::jsonb)
                  from (select * from expenses where spent_on >= d1 and spent_on < d2 order by amount desc limit 15) y));
end $$;

-- المشتريات: إجمالي/مدفوع/متبقي + بالنوع + بالمورد
create or replace function public.ai_purchases(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); d1 date; d2 date;
begin
  perform ai__chk(p_from, p_to);
  d1 := (p_from at time zone tz)::date; d2 := (p_to at time zone tz)::date;
  return jsonb_build_object(
    'count', (select count(*) from purchases where bought_on >= d1 and bought_on < d2),
    'total', (select coalesce(sum(total), 0) from purchases where bought_on >= d1 and bought_on < d2),
    'paid', (select coalesce(sum(paid), 0) from purchases where bought_on >= d1 and bought_on < d2),
    'unpaid', (select coalesce(sum(total - paid), 0) from purchases where bought_on >= d1 and bought_on < d2),
    'by_kind', (select coalesce(jsonb_agg(jsonb_build_object('kind', k, 'total', t, 'count', n) order by t desc), '[]'::jsonb)
                  from (select kind k, sum(total) t, count(*) n from purchases where bought_on >= d1 and bought_on < d2 group by 1) x),
    'by_supplier', (select coalesce(jsonb_agg(jsonb_build_object('supplier', s, 'total', t, 'unpaid', u) order by t desc), '[]'::jsonb)
                  from (select coalesce(su.name, 'بدون مورد') s, sum(p.total) t, sum(p.total - p.paid) u
                          from purchases p left join suppliers su on su.id = p.supplier_id
                         where p.bought_on >= d1 and p.bought_on < d2 group by 1 order by 2 desc limit 15) y));
end $$;

-- العملاء: جدد، نشطين، راجعين، وأعلى 5 إنفاقًا (برقم العميل بس؛ الاسم لو p_names)
create or replace function public.ai_customers(p_from timestamptz, p_to timestamptz, p_names boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  perform ai__chk(p_from, p_to);
  return jsonb_build_object(
    'customers_total', (select count(*) from customers),
    'new_in_range', (select count(*) from customers where created_at >= p_from and created_at < p_to),
    'active_in_range', (select count(distinct customer_id) from invoices where customer_id is not null and created_at >= p_from and created_at < p_to),
    'repeat_in_range', (select count(*) from (select customer_id from invoices where customer_id is not null and created_at >= p_from and created_at < p_to group by 1 having count(*) >= 2) z),
    'anonymous_invoices', (select count(*) from invoices where customer_id is null and created_at >= p_from and created_at < p_to),
    'top_spenders', (select coalesce(jsonb_agg(jsonb_build_object('customer_id', cid, 'spent', s, 'invoices', n)
                       || case when p_names then jsonb_build_object('name', (select name from customers c where c.id = cid)) else '{}'::jsonb end order by s desc), '[]'::jsonb)
                       from (select customer_id cid, sum(total) s, count(*) n from invoices
                              where customer_id is not null and created_at >= p_from and created_at < p_to
                              group by 1 order by 2 desc limit 5) x));
end $$;

-- الحجوزات: بالحالة وبالمصدر ونسبة عدم الحضور
create or replace function public.ai_appointments(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); d1 date; d2 date; v_tot int; v_ns int;
begin
  perform ai__chk(p_from, p_to);
  d1 := (p_from at time zone tz)::date; d2 := (p_to at time zone tz)::date;
  select count(*), count(*) filter (where status::text = 'no_show' or no_show_at is not null) into v_tot, v_ns from appointments where day >= d1 and day < d2;
  return jsonb_build_object('total', v_tot, 'no_show', v_ns,
    'no_show_pct', case when v_tot > 0 then round(v_ns * 100.0 / v_tot, 1) else null end,
    'by_status', (select coalesce(jsonb_agg(jsonb_build_object('status', s, 'count', n) order by n desc), '[]'::jsonb)
                    from (select status::text s, count(*) n from appointments where day >= d1 and day < d2 group by 1) x),
    'by_source', (select coalesce(jsonb_agg(jsonb_build_object('source', s, 'count', n) order by n desc), '[]'::jsonb)
                    from (select coalesce(booking_source, 'غير محدد') s, count(*) n from appointments where day >= d1 and day < d2 group by 1) y),
    'by_period', (select coalesce(jsonb_agg(jsonb_build_object('period', s, 'count', n) order by n desc), '[]'::jsonb)
                    from (select coalesce(period, 'غير محدد') s, count(*) n from appointments where day >= d1 and day < d2 group by 1) z));
end $$;

-- الحضور: لكل موظف أيام وساعات ودقائق تأخير
create or replace function public.ai_attendance(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz();
begin
  perform ai__chk(p_from, p_to);
  return jsonb_build_object('staff', (select coalesce(jsonb_agg(jsonb_build_object('name', n, 'role', r, 'days', d, 'hours', h, 'late_minutes', l) order by l desc, n), '[]'::jsonb)
    from (select pr.full_name n, pr.role::text r, count(distinct (a.check_in at time zone tz)::date) d,
                 round(coalesce(sum(extract(epoch from (a.check_out - a.check_in)) / 3600.0) filter (where a.check_out is not null), 0)::numeric, 1) h,
                 coalesce(sum(a.late_min), 0) l
            from attendance a join profiles pr on pr.id = a.staff_id
           where a.check_in >= p_from and a.check_in < p_to group by pr.id, pr.full_name, pr.role) x));
end $$;

-- الاستكشاف: الفواتير اللي بتكوّن الإجمالي (بفلاتر اختيارية). الأسماء بس لو p_names.
create or replace function public.ai_invoices(p_from timestamptz, p_to timestamptz, p_barber uuid default null, p_service text default null,
                                              p_method text default null, p_limit int default 30, p_names boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); v_lim int := least(greatest(coalesce(p_limit, 30), 1), 100); v_n int; v_sum numeric;
begin
  perform ai__chk(p_from, p_to);
  select count(*), coalesce(sum(i.total), 0) into v_n, v_sum from invoices i
   where i.created_at >= p_from and i.created_at < p_to and (p_barber is null or i.barber_id = p_barber)
     and (p_method is null or i.payment_method = p_method)
     and (p_service is null or exists (select 1 from invoice_items x where x.invoice_id = i.id and x.name = p_service));
  return jsonb_build_object('matching', v_n, 'matching_total', v_sum, 'shown', least(v_n, v_lim),
    'invoices', (select coalesce(jsonb_agg(row order by ts desc), '[]'::jsonb) from (
       select i.created_at ts, jsonb_build_object('id', i.id, 'no', i.no, 'at', to_char(i.created_at at time zone tz, 'YYYY-MM-DD HH24:MI'),
                'total', i.total, 'discount', i.discount, 'unpaid', i.unpaid, 'method', i.payment_method,
                'barber', (select full_name from profiles where id = i.barber_id),
                'items', (select coalesce(jsonb_agg(x.name || ' ×' || x.qty), '[]'::jsonb) from invoice_items x where x.invoice_id = i.id))
              || case when p_names then jsonb_build_object('customer', (select name from customers c where c.id = i.customer_id)) else '{}'::jsonb end row
         from invoices i
        where i.created_at >= p_from and i.created_at < p_to and (p_barber is null or i.barber_id = p_barber)
          and (p_method is null or i.payment_method = p_method)
          and (p_service is null or exists (select 1 from invoice_items x where x.invoice_id = i.id and x.name = p_service))
        order by i.created_at desc limit v_lim) q));
end $$;

-- حد الأسئلة اليومي للإدارة (60 افتراضي) — نفس assistant_hit لكن مع دور الإدارة
create or replace function public.assistant_hit()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_uid uuid := auth.uid(); v_role text; v_staff boolean; v_lim int; v_n int; v_on text; v_day date; v_key text;
  v_tz text := coalesce(nullif(trim(both '"' from (select value::text from app_settings where key = 'timezone')), ''), 'Africa/Cairo');
begin
  if v_uid is null then raise exception 'سجّل دخولك الأول'; end if;
  select coalesce(trim(both '"' from (select value::text from app_settings where key = 'assistant_enabled')), 'true') into v_on;
  if v_on in ('false', '0', 'off') then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  select p.role::text into v_role from profiles p where p.id = v_uid;
  v_staff := v_role in ('owner', 'manager', 'cashier', 'barber', 'assistant');
  v_key := case when v_role in ('owner', 'manager') then 'assistant_limit_admin' when v_staff then 'assistant_limit_staff' else 'assistant_limit_customer' end;
  v_lim := coalesce(nullif(trim(both '"' from (select value::text from app_settings where key = v_key)), '')::int,
             case when v_role in ('owner', 'manager') then 60 when v_staff then 40 else 20 end);
  v_day := (now() at time zone v_tz)::date;
  insert into assistant_usage(user_id, day, n) values (v_uid, v_day, 1)
    on conflict (user_id, day) do update set n = assistant_usage.n + 1
    returning n into v_n;
  if v_n > v_lim then
    update assistant_usage set n = v_lim where user_id = v_uid and day = v_day;
    return jsonb_build_object('ok', false, 'reason', 'limit', 'limit', v_lim);
  end if;
  return jsonb_build_object('ok', true, 'left', v_lim - v_n, 'role', coalesce(v_role, 'customer'));
end $$;
revoke all on function public.assistant_hit() from public, anon;
grant execute on function public.assistant_hit() to authenticated;

do $$ declare f text; begin
  foreach f in array array[
    'ai_overview(timestamptz,timestamptz)', 'ai_items_rank(timestamptz,timestamptz,text,int)', 'ai_daily_series(timestamptz,timestamptz)',
    'ai_expenses(timestamptz,timestamptz,boolean)', 'ai_purchases(timestamptz,timestamptz)', 'ai_customers(timestamptz,timestamptz,boolean)',
    'ai_appointments(timestamptz,timestamptz)', 'ai_attendance(timestamptz,timestamptz)',
    'ai_invoices(timestamptz,timestamptz,uuid,text,text,int,boolean)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
