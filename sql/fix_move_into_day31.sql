-- ============================================================================
-- ضمّ فواتير 1750 و1751 و1753 و1754 وسلفة 120 (اللي عدّلت تاريخها لـ 31/10) ليوم العمل 31 المفتوح.
-- السبب: التاريخ كان 31/10 لكن الساعة بعد منتصف الليل (12:01 لـ 1:26 صباحًا)، وده جوه فترة يوم 30
-- (اللي اتقفل 7:37 مساء 31/10). فالتطبيق كان بيحسبهم على يوم 30 المقفول ومش على الدرج الحالي.
-- بنحرّك الساعة بس لـ 8 مساءً (نفس التاريخ 31/10)، فيدخلوا في يوم 31. مفيش حاجة بتتمسح.
-- بيشتغل مرة واحدة: بعد التحريك مابيلاقيش حاجة قبل بداية يوم 31.
-- ============================================================================
do $$
declare v_start timestamptz := p24b_start('2026-10-31'); v_open boolean; n1 int; n2 int;
begin
  select exists (select 1 from business_days where day = '2026-10-31' and closed_at is null) into v_open;
  if not v_open then raise notice 'يوم 31 مش مفتوح — مفيش تعديل'; return; end if;
  -- نفس الدقيقة بعد منتصف الليل تتحول لنفس الدقيقة بعد 8 مساءً (إزاحة 20 ساعة)
  update loyalty_ledger set created_at = created_at + interval '20 hours'
   where invoice_id in (select id from invoices where no in (1750,1751,1753,1754) and created_at < v_start and created_at >= '2026-10-31 00:00+02');
  update invoices set created_at = created_at + interval '20 hours'
   where no in (1750,1751,1753,1754) and created_at < v_start and created_at >= '2026-10-31 00:00+02';
  get diagnostics n1 = row_count;
  update staff_transactions set created_at = created_at + interval '20 hours'
   where kind = 'advance' and amount = 120 and created_at = '2026-10-31 01:22:00+02' and created_at < v_start;
  get diagnostics n2 = row_count;
  raise notice 'اتحرّك % فاتورة و% سلفة', n1, n2;
end $$;
