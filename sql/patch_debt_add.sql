-- patch_debt_add.sql — تسجيل دين/آجل يدوي (من غير فاتورة) — للمدير/المالك بس
-- بيعمل صف في invoices بإجمالي 0 ودين = المبلغ، فيظهر في debts_list ويتحصّل بـ debt_collect زي أي دين.
-- الإيراد بيتحسب وقت التحصيل (زي الديون الجزئية). مفيش تأثير على الدرج لحد ما العميل يسدّد.
create or replace function public.debt_add(p_customer bigint, p_name text, p_phone text, p_amount numeric, p_note text default null, p_date date default null)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_nm text := nullif(btrim(coalesce(p_name, '')), ''); v_ph text := nullif(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), ''); v_id bigint; v_at timestamptz;
begin
  if not coalesce(is_mgr(), false) then raise exception 'تسجيل دين يدوي للمدير بس'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'اكتب مبلغ الدين'; end if;
  if p_customer is null and v_nm is null then raise exception 'اختار العميل أو اكتب اسمه'; end if;
  if p_customer is not null and not exists (select 1 from customers where id = p_customer) then raise exception 'العميل مش موجود'; end if;
  if p_date is not null and p_date > (now() at time zone my_tz())::date then raise exception 'تاريخ الدين في المستقبل'; end if;
  v_at := case when p_date is null then now() else (p_date::timestamp + time '12:00') at time zone my_tz() end;
  insert into invoices(customer_id, subtotal, discount, total, payment_method, unpaid, debtor_name, debtor_phone, created_at)
  values (p_customer, 0, 0, 0, 'cash', round(p_amount, 2), v_nm, v_ph, v_at) returning id into v_id;
  if nullif(btrim(coalesce(p_note, '')), '') is not null then
    begin insert into audit_log(table_name, op, row_id, actor, summary) values ('invoices', 'debt_add', v_id::text, auth.uid(), left('دين يدوي: ' || p_note, 200)); exception when others then null; end;
  end if;
  return v_id;
end $$;
revoke all on function public.debt_add(bigint, text, text, numeric, text, date) from public, anon;
grant execute on function public.debt_add(bigint, text, text, numeric, text, date) to authenticated;
-- تراجع: drop function public.debt_add(bigint,text,text,numeric,text,date);  (والدين المسجّل يتشال بحذف الفاتورة من المدير)
