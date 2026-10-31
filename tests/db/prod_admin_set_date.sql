-- نسخة من admin_set_date زي ما هي في الإنتاج (للاختبار المحلي بس)
CREATE OR REPLACE FUNCTION public.admin_set_date(p_kind text, p_id text, p_ts timestamp with time zone, p_force boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_tbl text; v_col text; v_is_ts boolean; v_old date; v_new date; v_closed date; v_no text;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'owner') then raise exception 'للمالك فقط'; end if;
  if p_ts is null then raise exception 'اكتب تاريخ صحيح'; end if;
  select t, c, ts into v_tbl, v_col, v_is_ts from (values
    ('invoice','invoices','created_at',true), ('expense','expenses','spent_on',false),
    ('staff_tx','staff_transactions','created_at',true), ('salary','salary_payments','paid_on',false),
    ('purchase','purchases','bought_on',false)) as m(k, t, c, ts) where m.k = p_kind;
  if v_tbl is null then raise exception 'النوع ده مش مدعوم'; end if;

  execute format(case when v_is_ts then 'select (%I at time zone my_tz())::date from %I where id::text = %L'
                      else 'select %I::date from %I where id::text = %L' end, v_col, v_tbl, p_id) into v_old;
  if v_old is null then raise exception 'السجل مش موجود'; end if;
  v_new := (p_ts at time zone my_tz())::date;
  if v_new > p16_today() then raise exception 'مينفعش تاريخ في المستقبل'; end if;

  -- لو اليوم القديم أو الجديد مقفول في الخزنة: اطلب تأكيد
  select min(day) into v_closed from cash_closings where day in (v_old, v_new);
  if v_closed is not null and not p_force then return jsonb_build_object('needs_force', true, 'day', v_closed); end if;

  if v_is_ts then execute format('update %I set %I = %L where id::text = %L', v_tbl, v_col, p_ts, p_id);
  else execute format('update %I set %I = %L where id::text = %L', v_tbl, v_col, v_new, p_id); end if;

  -- بنود الفاتورة لو ليها تاريخ خاص بيها
  if p_kind = 'invoice' and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'invoice_items' and column_name = 'created_at') then
    update invoice_items set created_at = p_ts where invoice_id::text = p_id;
  end if;
  return jsonb_build_object('ok', true, 'from', v_old, 'to', v_new);
end $function$;
