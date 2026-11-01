-- ============================================================================
-- تعديل وقت فتح/قفل يوم عمل (للمالك فقط).
-- • تعديل وقت القفل بيحرّك الحد الفاصل بين اليوم واللي بعده: الحاجات اللي ساعتها قبل الوقت الجديد
--   بتتحسب على اليوم ده، وبعده على اليوم اللي بعده. مفيش فواتير ولا مصروفات بتتحذف أو بتتعدّل.
-- • بعد التعديل أرقام "المتوقع" في جرد اليوم ده واللي بعده بتتحدّث (العدّ الفعلي ما بيتغيّرش)،
--   والقديم بيتسجل في deletion_log.
-- • اليوم المفتوح: بتعدّل وقت الفتح بس (القفل من شاشة الخزنة بجرد الدرج).
-- آمن للتكرار (create or replace).
-- ============================================================================
create or replace function public.p32_refresh_closing(p_day date, p_reason text) returns boolean
language plpgsql security definer set search_path to 'public' as $$
declare cl cash_closings; f jsonb; v_ec numeric; v_ecard numeric; v_ew numeric;
begin
  select * into cl from cash_closings where day = p_day;
  if cl.id is null then return false; end if;
  f := day_figures(p_day);
  v_ec := expected_cash_of(f, cl.opening); v_ecard := (f->>'card_sales')::numeric; v_ew := (f->>'wallet_sales')::numeric;
  if v_ec is not distinct from cl.expected_cash and v_ecard is not distinct from cl.expected_card and v_ew is not distinct from cl.expected_wallet then return false; end if;
  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
    values ('cash_closings', cl.id::text, to_jsonb(cl), jsonb_build_object('reason', p_reason), auth.uid());
  update cash_closings set expected_cash = v_ec, diff_cash = counted_cash - v_ec,
         expected_card = v_ecard, diff_card = counted_card - v_ecard,
         expected_wallet = v_ew, diff_wallet = counted_wallet - v_ew, breakdown = f
   where id = cl.id;
  return true;
end $$;
revoke execute on function public.p32_refresh_closing(date, text) from public, anon, authenticated;

create or replace function public.edit_business_day(p_day date, p_opened_at timestamptz default null, p_closed_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare b business_days; v_open timestamptz; v_close timestamptz; v_prev timestamptz; v_next business_days; r1 boolean := false; r2 boolean := false;
begin
  if not is_owner() then raise exception 'للمالك فقط'; end if;
  select * into b from business_days where day = p_day;
  if b.day is null then raise exception 'اليوم ده مش متسجل كيوم عمل'; end if;
  if p_closed_at is not null and b.closed_at is null then
    raise exception 'اليوم ده لسه مفتوح — اقفله من الخزنة بجرد الدرج الأول، وبعدين عدّل وقت القفل'; end if;
  if p_opened_at is null and p_closed_at is null then raise exception 'اكتب وقت الفتح أو القفل'; end if;
  v_open := coalesce(p_opened_at, b.opened_at); v_close := coalesce(p_closed_at, b.closed_at);
  if v_open > now() + interval '2 minutes' then raise exception 'وقت الفتح في المستقبل'; end if;
  if v_close is not null then
    if v_close <= v_open then raise exception 'وقت القفل لازم يكون بعد وقت الفتح'; end if;
    if v_close > now() + interval '2 minutes' then raise exception 'وقت القفل في المستقبل'; end if;
    select max(closed_at) into v_prev from business_days where closed_at is not null and day < p_day;
    if v_prev is not null and v_close <= v_prev then raise exception 'وقت القفل لازم يكون بعد قفل اليوم اللي قبله'; end if;
    select * into v_next from business_days where day > p_day order by day limit 1;
    if v_next.day is not null and v_next.closed_at is not null and v_close >= v_next.closed_at then
      raise exception 'وقت القفل لازم يكون قبل قفل اليوم اللي بعده'; end if;
  end if;
  insert into deletion_log(table_name, row_id, row_data, extra, deleted_by)
    values ('business_days', p_day::text, to_jsonb(b), jsonb_build_object('reason', 'edit_business_day'), auth.uid());
  update business_days set opened_at = v_open, closed_at = v_close where day = p_day;
  if p_closed_at is not null and p_closed_at is distinct from b.closed_at then
    r1 := p32_refresh_closing(p_day, 'edit_business_day: recomputed expected');
    if v_next.day is not null then r2 := p32_refresh_closing(v_next.day, 'edit_business_day: recomputed expected (next day)'); end if;
  end if;
  return jsonb_build_object('day', p_day, 'opened_at', v_open, 'closed_at', v_close, 'refreshed_closing', r1, 'refreshed_next_closing', r2);
end $$;
revoke all on function public.edit_business_day(date, timestamptz, timestamptz) from public, anon;
grant execute on function public.edit_business_day(date, timestamptz, timestamptz) to authenticated;
