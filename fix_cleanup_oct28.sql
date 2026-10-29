-- تنضيف بيانات: (1) رواتب الشهر الماضي اللي اتسجلت مصروفات قبل تشغيل النظام تتنقل لآخر الشهر الماضي
--               (2) إنهاء حضور اتنسى من غير انصراف (أكتر من 20 ساعة) بانصراف بعد 12 ساعة من الحضور
-- بيتشغل مرة واحدة، ولو اتشغل تاني ما بيغيّرش حاجة.
do $$
declare n1 int; n2 int;
begin
  update expenses
     set spent_on = date '2026-09-30', note = coalesce(note,'') || ' (رواتب الشهر الماضي قبل تشغيل النظام)'
   where id in (20, 16, 12, 17) and category = 'أخرى' and spent_on between date '2026-10-06' and date '2026-10-10'
     and coalesce(note,'') like 'راتب%' and coalesce(note,'') not like '%قبل تشغيل النظام%';
  get diagnostics n1 = row_count;

  update attendance
     set check_out = least(check_in + interval '12 hours', now()),
         note = coalesce(nullif(note,'') || ' — ', '') || 'انصراف تلقائي (اتنسى تسجيل الانصراف)'
   where check_out is null and check_in < now() - interval '20 hours';
  get diagnostics n2 = row_count;
  raise notice 'مصروفات اتنقلت: %، حضور اتقفل: %', n1, n2;
end $$;
select id, spent_on, amount, note from expenses where id in (20,16,12,17) order by id;
select id, staff_id, check_in, check_out from attendance where note like '%انصراف تلقائي%' order by id;
