-- ============================================================================
-- تصحيح جرد يوم 30/10 (مرة واحدة):
-- الجرد اتسجل 5540 وقت القفل، لكن الرقم ده كان فيه كاش النهارده (31/10) اللي لسه ما اتسجلش
-- وقتها (فواتير 1731 لـ 1738 اتسجلت بعد القفل ومحسوبة على يوم 31).
-- المتوقع الحقيقي لنهاية يوم 30 = 3865 (رصيد أول اليوم 2910 + مبيعات كاش 1846 - مصروفات 60 - سلف 831).
-- بنخلي عدّ يوم 30 = 3865 فيبقى رصيد أول يوم 31 = 3865، ومبيعات يوم 31 ماتتحسبش مرتين.
-- القيم القديمة بتتسجل في deletion_log قبل التعديل. الفواتير والمصروفات ماتتلمسش.
-- بيشتغل بس لو الجرد لسه 5540 بالظبط (لو اتغيّر، مابيعملش حاجة).
-- ============================================================================
do $$
declare r cash_closings;
begin
  select * into r from cash_closings where day = '2026-10-30' and counted_cash = 5540 and expected_cash = 3865 and diff_cash = 1675;
  if found then
    insert into deletion_log(table_name, row_id, row_data, extra)
      values ('cash_closings', r.id::text, to_jsonb(r), jsonb_build_object('reason', 'correct_close_day30: counted 5540 -> 3865'));
    update cash_closings set counted_cash = 3865, diff_cash = 0, note = coalesce(note || ' | ', '') || 'اتصحح: العدّ الأصلي 5540 كان فيه كاش يوم 31' where id = r.id;
  end if;
end $$;
