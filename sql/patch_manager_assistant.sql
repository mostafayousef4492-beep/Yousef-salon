-- مساعد المدير: أسئلة تشغيلية (خطوات الاستخدام + أرقام موظف + بيانات عميل) — قراءة فقط.
-- • مساعد التحليل (patch_admin_assistant.sql) بقى للمالك بس: ai_admin_ok() = owner.
-- • ai_mgr_ok(): مالك دايمًا، والمدير ما لم يكن assistant_manager_enabled = false في app_settings (افتراضي true).
-- • ai_mode(): 'owner' | 'manager' | null — الواجهة بتستخدمها تعرف تفتح أنهي مساعد.
-- • كل الدوال stable (قراءة بس) وبتبدأ بفحص ai_mgr_ok(). مفيش تليفونات عملاء بترجع منها خالص.
-- آمن للتكرار. مفيش بيانات بتتغير.
create or replace function public.ai_admin_ok() returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
begin
  return coalesce((select p.role::text = 'owner' from profiles p where p.id = auth.uid()), false);
end $$;

create or replace function public.ai_mgr_ok() returns boolean
language plpgsql stable security definer set search_path to 'public' as $$
declare v_role text; v_set text;
begin
  select p.role::text into v_role from profiles p where p.id = auth.uid();
  if v_role = 'owner' then return true; end if;
  if v_role = 'manager' then
    select trim(both '"' from value::text) into v_set from app_settings where key = 'assistant_manager_enabled';
    return coalesce(v_set, 'true') not in ('false', '0', 'off');
  end if;
  return false;
end $$;

create or replace function public.ai_mode() returns text
language sql stable security definer set search_path to 'public' as $$
  select case when ai_admin_ok() then 'owner' when ai_mgr_ok() then 'manager' else null end $$;

create or replace function public.ai__chk_mgr() returns void
language plpgsql stable set search_path to 'public' as $$
begin if not ai_mgr_ok() then raise exception 'غير مصرح'; end if; end $$;

-- موظفين بالاسم أو الكود
create or replace function public.ai_find_staff(p_q text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare q text := nullif(trim(coalesce(p_q, '')), '');
begin
  perform ai__chk_mgr();
  if q is null or length(q) < 1 then raise exception 'اكتب اسم الموظف'; end if;
  return jsonb_build_object('staff', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', full_name, 'role', role::text, 'code', code) order by full_name), '[]'::jsonb)
    from (select * from profiles where role::text <> 'customer' and (full_name ilike '%' || q || '%' or code = q) order by full_name limit 8) x));
end $$;

-- أرقام موظف في فترة: ملخص + حركات (سحب/خصم/مكافأة) + المصروف من الراتب + الرصيد
create or replace function public.ai_staff_money(p_staff uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare s jsonb; st jsonb; pr profiles;
begin
  perform ai__chk_mgr();
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'الفترة غير صحيحة'; end if;
  if p_to - p_from > interval '400 days' then raise exception 'الفترة أطول من 400 يوم'; end if;
  select * into pr from profiles where id = p_staff and role::text <> 'customer';
  if not found then raise exception 'موظف غير موجود'; end if;
  select to_jsonb(x) into s from staff_summary(p_staff, p_from, p_to) x;
  begin st := staff_statement(p_staff, null, now()); exception when others then st := null; end;
  return jsonb_build_object('name', pr.full_name, 'role', pr.role::text, 'commission_pct', pr.commission_pct, 'monthly_salary', pr.salary,
    'summary', s,
    'transactions', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'amount', amount, 'note', note, 'at', created_at) order by created_at desc), '[]'::jsonb)
                       from (select * from staff_transactions where staff_id = p_staff and created_at >= p_from and created_at < p_to order by created_at desc limit 50) t),
    'salary_paid_in_range', (select coalesce(sum(amount), 0) from salary_payments where staff_id = p_staff and created_at >= p_from and created_at < p_to),
    'balance_now', case when st is null then null else (st->>'closing')::numeric end);
end $$;

-- حضور موظف
create or replace function public.ai_staff_attendance(p_staff uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); pr profiles;
begin
  perform ai__chk_mgr();
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'الفترة غير صحيحة'; end if;
  if p_to - p_from > interval '400 days' then raise exception 'الفترة أطول من 400 يوم'; end if;
  select * into pr from profiles where id = p_staff and role::text <> 'customer';
  if not found then raise exception 'موظف غير موجود'; end if;
  return jsonb_build_object('name', pr.full_name,
    'days_present', (select count(distinct (check_in at time zone tz)::date) from attendance where staff_id = p_staff and check_in >= p_from and check_in < p_to),
    'total_hours', (select round(coalesce(sum(extract(epoch from (check_out - check_in)) / 3600.0) filter (where check_out is not null), 0)::numeric, 1) from attendance where staff_id = p_staff and check_in >= p_from and check_in < p_to),
    'total_late_minutes', (select coalesce(sum(late_min), 0) from attendance where staff_id = p_staff and check_in >= p_from and check_in < p_to),
    'records', (select coalesce(jsonb_agg(jsonb_build_object('in', to_char(check_in at time zone tz, 'YYYY-MM-DD HH24:MI'), 'out', case when check_out is null then null else to_char(check_out at time zone tz, 'YYYY-MM-DD HH24:MI') end, 'late_min', late_min) order by check_in desc), '[]'::jsonb)
                  from (select * from attendance where staff_id = p_staff and check_in >= p_from and check_in < p_to order by check_in desc limit 31) a));
end $$;

-- عملاء بالاسم أو الموبايل (من غير ما يرجّع الموبايل)
create or replace function public.ai_customer_find(p_q text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare q text := nullif(trim(coalesce(p_q, '')), ''); d text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
begin
  perform ai__chk_mgr();
  if q is null or length(q) < 2 then raise exception 'اكتب حرفين على الأقل من اسم العميل أو رقمه'; end if;
  return jsonb_build_object('customers', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'visits', visits, 'points', points) order by name), '[]'::jsonb)
    from (select * from customers where name ilike '%' || q || '%' or (length(d) >= 4 and phone like '%' || d || '%') order by name limit 6) x));
end $$;

-- ملف عميل: نقاط وزيارات وإنفاق وديون وآخر فواتير وحجوزات (بدون موبايل)
create or replace function public.ai_customer_info(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare tz text := my_tz(); c customers;
begin
  perform ai__chk_mgr();
  select * into c from customers where id = p_id;
  if not found then raise exception 'عميل غير موجود'; end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'points', c.points, 'lifetime_points', c.lifetime_points, 'visits', c.visits,
    'joined', to_char(c.created_at at time zone tz, 'YYYY-MM-DD'), 'has_app_account', c.user_id is not null, 'has_phone', c.phone is not null,
    'invoices_count', (select count(*) from invoices where customer_id = c.id and settles_invoice is null),
    'total_spent', (select coalesce(sum(total), 0) from invoices where customer_id = c.id),
    'last_visit', (select to_char(max(created_at) at time zone tz, 'YYYY-MM-DD') from invoices where customer_id = c.id and settles_invoice is null),
    'debt_remaining', (select coalesce(sum(remaining), 0) from debts_list(c.id)),
    'recent_invoices', (select coalesce(jsonb_agg(jsonb_build_object('no', no, 'at', to_char(created_at at time zone tz, 'YYYY-MM-DD HH24:MI'), 'total', total, 'unpaid', unpaid, 'barber', (select full_name from profiles where id = barber_id),
                          'items', (select coalesce(jsonb_agg(name || ' ×' || qty), '[]'::jsonb) from invoice_items x where x.invoice_id = i.id)) order by created_at desc), '[]'::jsonb)
                          from (select * from invoices where customer_id = c.id order by created_at desc limit 6) i),
    'recent_appointments', (select coalesce(jsonb_agg(jsonb_build_object('day', day, 'period', period, 'status', status::text) order by day desc, id desc), '[]'::jsonb)
                          from (select * from appointments where customer_id = c.id order by day desc, id desc limit 5) a));
end $$;

do $$ declare f text; begin
  foreach f in array array['ai_admin_ok()', 'ai_mgr_ok()', 'ai_mode()', 'ai__chk_mgr()', 'ai_find_staff(text)', 'ai_staff_money(uuid,timestamptz,timestamptz)',
    'ai_staff_attendance(uuid,timestamptz,timestamptz)', 'ai_customer_find(text)', 'ai_customer_info(bigint)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- الحد اليومي: نفس مفتاح الإدارة للاتنين (assistant_limit_admin، 60) — assistant_hit في patch_admin_assistant.sql بيغطي owner وmanager.
