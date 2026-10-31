-- ============================================================================
-- 1) إصلاح: يوم العمل اللي بيفضل مفتوح بعد الساعة 6 الصبح كان بيتعامل كأنه "يوم قديم"
--    فبيتقفل بوقت غلط (قبل ما يتفتح بيوم)، وبيختفي إيراده من تقارير اليوم.
--    دلوقتي الإزاحة بتشتغل بس لليوم اللي اتفتح بتاريخ قديم (فتح بتاريخ مختار).
-- 2) إصلاح بيانات: يوم اتقفل بوقت غلط يترجّع لوقت القفل الحقيقي (من جدول الجرد).
-- 3) جديد: reopen_business_day — المالك بس يعيد فتح آخر يوم اتقفل ويعدّل فيه.
-- مفيش حذف لأي فواتير ولا مصروفات. الجرد القديم بيتسجل في deletion_log قبل ما يتشال.
-- ============================================================================

create or replace function biz_shift_days() returns integer
language sql stable security definer set search_path to 'public' as $$
  select coalesce((select case when b.opened_at <= (b.day::timestamp at time zone my_tz())
                               then least(0, b.day - biz_natural_day()) else 0 end
                     from business_days b where b.closed_at is null limit 1), 0) $$;

create or replace function business_day_state() returns jsonb
language sql stable security definer set search_path to 'public' as $$
  select case when b.day is null
    then jsonb_build_object('open', false, 'day', (now() at time zone my_tz())::date, 'calendar', (now() at time zone my_tz())::date, 'natural', biz_natural_day(), 'backdated', false)
    else jsonb_build_object('open', true, 'day', b.day, 'opened_at', b.opened_at, 'window_from', p24b_start(b.day),
                            'calendar', (now() at time zone my_tz())::date, 'natural', biz_natural_day(),
                            'backdated', b.opened_at <= (b.day::timestamp at time zone my_tz()) and b.day < biz_natural_day())
  end
  from (select 1) x left join business_days b on b.closed_at is null $$;

-- إصلاح البيانات: أيام اتقفلت وقت القفل فيها قبل وقت الفتح (الخلل ده بس)
update business_days b set closed_at = c.created_at
  from cash_closings c
 where c.day = b.day and b.closed_at is not null and b.closed_at < b.opened_at and c.created_at > b.opened_at;

create or replace function reopen_business_day(p_day date default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare v_day date; v_last date; r cash_closings;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  if exists (select 1 from business_days where closed_at is null) then
    raise exception 'فيه يوم مفتوح بالفعل. اقفله الأول وبعدين أعد فتح اللي قبله.'; end if;
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
