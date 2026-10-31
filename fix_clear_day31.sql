-- ============================================================================
-- تفضية يوم 31/10: نقل شغل النهارده اللي اتسجل بعد قفل يوم 30 (فواتير 1731 لـ 1738 + سلفة 120)
-- ليوم 30، لأن كاشهم كان جوه الـ5540 اللي اتعدّت وقت القفل. يوم 31 يفضل فاضي.
-- بيتنقلوا ليوم 30 بنفس الساعة (إزاحة يوم لورا)، ومفيش حاجة بتتمسح.
-- بعد النقل بنحدّث سجل جرد يوم 30 بالأرقام الجديدة (المتوقع يبقى 4975، والفرق +565).
-- القيمة القديمة للجرد بتتسجل في deletion_log. العدّ الفعلي (5540) ما بيتغيّرش.
-- بيشتغل مرة واحدة بس: لو الفواتير اتنقلت قبل كده مابيعملش حاجة.
-- ============================================================================
do $$
declare cl cash_closings; v_close timestamptz; n int; f jsonb; v_open numeric; v_exp numeric;
begin
  select closed_at into v_close from business_days where day = '2026-10-30' and closed_at is not null;
  select * into cl from cash_closings where day = '2026-10-30';
  if v_close is null or cl.id is null then raise notice 'يوم 30 مش مقفول بجرد — مفيش تعديل'; return; end if;

  -- الفواتير: بس الأرقام دي، وبس اللي اتسجلت بعد قفل يوم 30
  update loyalty_ledger l set created_at = l.created_at - interval '1 day'
    where l.invoice_id in (select id from invoices where no between 1731 and 1738 and created_at >= v_close);
  update invoices set created_at = created_at - interval '1 day' where no between 1731 and 1738 and created_at >= v_close;
  get diagnostics n = row_count;
  -- السلفة الكاش اللي اتسجلت بعد القفل
  update staff_transactions set created_at = created_at - interval '1 day'
    where kind = 'advance' and amount = 120 and created_at >= v_close and created_at < v_close + interval '6 hours';

  if n > 0 then
    insert into deletion_log(table_name, row_id, row_data, extra)
      values ('cash_closings', cl.id::text, to_jsonb(cl), jsonb_build_object('reason', 'clear_day31: moved invoices 1731-1738 + advance 120 to day 30'));
    f := day_figures('2026-10-30');
    v_open := (f->>'opening')::numeric;
    v_exp := expected_cash_of(f, v_open);
    update cash_closings set expected_cash = v_exp, diff_cash = counted_cash - v_exp,
           expected_card = (f->>'card_sales')::numeric, diff_card = counted_card - (f->>'card_sales')::numeric,
           expected_wallet = (f->>'wallet_sales')::numeric, diff_wallet = counted_wallet - (f->>'wallet_sales')::numeric,
           breakdown = f
     where id = cl.id;
  end if;
  raise notice 'اتنقل % فاتورة ليوم 30', n;
end $$;
