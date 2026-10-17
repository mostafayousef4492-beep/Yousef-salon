-- تعديل تاريخ فاتورة / مصروف / حركة موظف (سحب، خصم، مكافأة) من غير حذف. للمالك بس.
-- لو اليوم (القديم أو الجديد) مقفول في الخزنة بيرجع needs_force عشان التأكيد.
create or replace function public.admin_set_date(p_table text, p_id bigint, p_day date, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare tz text := my_tz(); v_old date; v_ts timestamptz; v_new timestamptz;
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  if p_day is null then raise exception 'اختار التاريخ'; end if;
  if p_day > (now() at time zone tz)::date then raise exception 'التاريخ لسه ماجاش'; end if;
  if p_table = 'invoices' then
    select created_at into v_ts from invoices where id = p_id for update;
  elsif p_table = 'staff_transactions' then
    select created_at into v_ts from staff_transactions where id = p_id for update;
  elsif p_table = 'expenses' then
    select spent_on::timestamp at time zone tz into v_ts from expenses where id = p_id for update;
  else raise exception 'جدول غير مدعوم'; end if;
  if v_ts is null then raise exception 'السجل مش موجود'; end if;
  v_old := (v_ts at time zone tz)::date;
  if v_old = p_day then return jsonb_build_object('saved', true, 'unchanged', true, 'day', p_day); end if;
  if p_table <> 'staff_transactions' and not p_force
     and exists (select 1 from cash_closings c where c.day in (v_old, p_day)) then
    return jsonb_build_object('saved', false, 'needs_force', true, 'old_day', v_old, 'day', p_day);
  end if;
  v_new := (p_day::text || ' ' || to_char(v_ts at time zone tz, 'HH24:MI:SS'))::timestamp at time zone tz;
  if p_table = 'invoices' then
    update invoices set created_at = v_new where id = p_id;
    update loyalty_ledger set created_at = v_new where invoice_id = p_id;
  elsif p_table = 'staff_transactions' then
    update staff_transactions set created_at = v_new where id = p_id;
  else
    update expenses set spent_on = p_day where id = p_id;
  end if;
  return jsonb_build_object('saved', true, 'old_day', v_old, 'day', p_day);
end $$;
revoke all on function public.admin_set_date(text,bigint,date,boolean) from public, anon;
grant execute on function public.admin_set_date(text,bigint,date,boolean) to authenticated;
