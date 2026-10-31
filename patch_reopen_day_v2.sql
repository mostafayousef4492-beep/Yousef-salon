-- ============================================================================
-- إصلاح فتح/قفل اليوم (النسخة 2):
-- 1) reopen_business_day: لو فيه يوم مفتوح بس فاضي (مفيهوش فواتير ولا مصروفات ولا حركة درج)
--    بيتشال تلقائي وبيرجع آخر يوم اتقفل مفتوح. لو فيه عمليات: بيرفض ويقولك تقفله.
-- 2) إصلاح حالة اليوم: يوم 30/10 كان جرده اتمسح من زرار المسح (اللي بيسيب اليوم مقفول من غير جرد)
--    ويوم 31 اتفتح فاضي. السكربت بيرجّع 30 مفتوح علشان تعدّ الدرج وتقفله بالرقم الصح.
--    (بيشتغل بس لو الشروط دي متحققة بالظبط، ولو اتشغّل مرتين مابيعملش حاجة.)
-- مفيش حذف لأي فواتير أو مصروفات. اليوم الفاضي بيتسجل في deletion_log.
-- ============================================================================
create or replace function p31_day_has_activity(p_since timestamptz) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from invoices where created_at >= p_since)
      or exists (select 1 from expenses where created_at >= p_since)
      or exists (select 1 from cash_moves where created_at >= p_since)
      or exists (select 1 from purchases where created_at >= p_since)
      or exists (select 1 from supplier_payments where created_at >= p_since)
      or exists (select 1 from salary_payments where created_at >= p_since)
      or exists (select 1 from staff_transactions where kind = 'advance' and created_at >= p_since)
      or exists (select 1 from cafe_sales where created_at >= p_since)
      or exists (select 1 from cafe_expenses where created_at >= p_since)
      or exists (select 1 from cafe_purchases where created_at >= p_since) $$;
revoke execute on function p31_day_has_activity(timestamptz) from public, anon, authenticated;

create or replace function reopen_business_day(p_day date default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_day date; v_last date; r cash_closings; o business_days;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  select * into o from business_days where closed_at is null;
  if found then
    if p31_day_has_activity(o.opened_at) then
      raise exception 'اليوم المفتوح (%) فيه عمليات. اقفله الأول بجرد الدرج وبعدين أعد فتح اللي قبله.', o.day; end if;
    insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
      values ('business_days', o.day::text, to_jsonb(o), jsonb_build_object('reason', 'reopen_previous_day_empty'), auth.uid());
    delete from business_days where day = o.day;
  end if;
  select max(day) into v_last from business_days;
  if v_last is null then raise exception 'مفيش أيام اتقفلت'; end if;
  v_day := coalesce(p_day, v_last);
  if v_day <> v_last then raise exception 'تقدر تعيد فتح آخر يوم اتقفل بس (%).', v_last; end if;
  select * into r from cash_closings where day = v_day;
  if found then
    insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
      values ('cash_closings', r.id::text, to_jsonb(r), jsonb_build_object('reason', 'reopen_business_day'), auth.uid());
    delete from cash_closings where id = r.id;
  end if;
  update business_days set closed_at = null, closed_by = null where day = v_day;
  return business_day_state();
end $$;
revoke execute on function reopen_business_day(date) from public, anon;
grant execute on function reopen_business_day(date) to authenticated;

-- إصلاح الحالة الحالية (مرة واحدة، بشروط صارمة)
do $$
declare o business_days; l business_days;
begin
  select * into o from business_days where closed_at is null;
  select * into l from business_days where closed_at is not null order by day desc limit 1;
  if o.day is not null and l.day is not null and o.day > l.day
     and not exists (select 1 from cash_closings c where c.day = l.day)
     and not p31_day_has_activity(o.opened_at) then
    insert into deletion_log(table_name, row_id, row_data, extra)
      values ('business_days', o.day::text, to_jsonb(o), jsonb_build_object('reason', 'repair_reopen_previous_day'));
    delete from business_days where day = o.day;
    update business_days set closed_at = null, closed_by = null where day = l.day;
  end if;
end $$;
