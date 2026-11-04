-- ضخ 600 من صاحب المحل اتسجّل على يوم 2/11 بالغلط (اتكتب 4/11 الساعة 3:13 ص)، وهو بتاع يوم 3/11
-- (اللي احمد سمير سحب فيه الـ2000 «جمعيه»). بننقله ليوم 3/11 وبنحدّث لقطة إقفال 3/11 بس.
-- المتوقع هيبقى 1410 + 2300 + 600 − 90 − 2380 = 1840 والمعدود 1860 → فرق +20 بدل +620.
-- بيشتغل مرة واحدة: لو الحركة مش على 2/11 بمبلغ 600 مش بيعدّل حاجة. مفيش حاجة بتتمسح.
begin;
do $$
declare n int;
begin
  update cash_moves set day = '2026-11-03' where id = 7 and day = '2026-11-02' and kind = 'deposit' and amount = 600;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'الحركة 7 مش على 2/11 بمبلغ 600 — اتوقف من غير تعديل'; end if;
  perform p32_refresh_closing('2026-11-03', 'نقل ضخ 600 من 2/11 لـ 3/11');
end $$;
select day, opening, expected_cash, counted_cash, diff_cash from cash_closings where day in ('2026-11-02','2026-11-03') order by day;
commit;
