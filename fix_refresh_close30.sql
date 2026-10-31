-- ============================================================================
-- تحديث أرقام "المتوقع" في جرد يوم 30/10 بعد مسح الفواتير المكررة (1731 لـ 1738).
-- العدّ الفعلي (5540) ما بيتغيّرش. بيتحسب المتوقع والفرق من أرقام اليوم الحالية.
-- القيمة القديمة بتتسجل في deletion_log. تشغيله مرتين مايضرّش.
-- شغّله بعد ما تمسح الفواتير المكررة من شاشة الفواتير.
-- ============================================================================
do $$
declare cl cash_closings; f jsonb; v_exp numeric;
begin
  select * into cl from cash_closings where day = '2026-10-30';
  if cl.id is null then raise notice 'مفيش جرد ليوم 30'; return; end if;
  f := day_figures('2026-10-30');
  v_exp := expected_cash_of(f, (f->>'opening')::numeric);
  if v_exp is distinct from cl.expected_cash or (f->>'wallet_sales')::numeric is distinct from cl.expected_wallet or (f->>'card_sales')::numeric is distinct from cl.expected_card then
    insert into deletion_log(table_name, row_id, row_data, extra)
      values ('cash_closings', cl.id::text, to_jsonb(cl), jsonb_build_object('reason', 'refresh_close30: recomputed expected after duplicate invoices removed'));
    update cash_closings set expected_cash = v_exp, diff_cash = counted_cash - v_exp,
           expected_card = (f->>'card_sales')::numeric, diff_card = counted_card - (f->>'card_sales')::numeric,
           expected_wallet = (f->>'wallet_sales')::numeric, diff_wallet = counted_wallet - (f->>'wallet_sales')::numeric,
           breakdown = f
     where id = cl.id;
    raise notice 'اتحدّث: المتوقع % والفرق %', v_exp, cl.counted_cash - v_exp;
  end if;
end $$;
