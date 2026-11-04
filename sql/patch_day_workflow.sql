-- تبسيط فتح/قفل اليوم:
--  1) close_day_preview(day): ملخص قبل القفل (المتوقع + أكبر بنود الخروج + حجوزات لسه في الدور).
--  2) move_entry_day(kind,id,day): المالك ينقل ضخ/سحب (cash_move) أو مصروف (expense) أو حركة موظف (staff_tx) ليوم تاني،
--     ولقطة إقفال اليومين (القديم والجديد) بتتحدّث تلقائي (العدّ الفعلي ما بيتغيّرش).
-- مفيش تعديل في أي دالة موجودة. آمن للتكرار.
begin;

create or replace function public.close_day_preview(p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb; s timestamptz; e timestamptz; big jsonb; pend int; upc int; v_open numeric;
begin
  if not (is_mgr() or has_perm('use_pos')) then raise exception 'غير مصرح'; end if;
  f := day_figures(p_day);
  s := coalesce(p24b_start(p_day), p_day::timestamptz);
  select coalesce(b.closed_at, now()) into e from business_days b where b.day = p_day;
  e := coalesce(e, now());
  select coalesce(jsonb_agg(jsonb_build_object('kind', u.k, 'who', u.w, 'amount', u.a, 'note', u.n) order by u.a desc), '[]'::jsonb) into big
  from (
    select * from (
      select 'سلفة موظف'::text k, p.full_name::text w, t.amount a, t.note::text n
        from staff_transactions t join profiles p on p.id = t.staff_id
       where t.kind = 'advance' and t.created_at >= s and t.created_at <= e
      union all
      select 'مصروف', x.category::text, x.amount, x.note::text
        from expenses x where x.spent_on = p_day and x.paid_from = 'drawer' and x.purchase_id is null
      union all
      select case m.kind when 'withdraw' then 'سحب من الدرج' else 'إضافة للدرج' end, ''::text, m.amount, m.note::text
        from cash_moves m where m.day = p_day
    ) z where z.a >= 300 order by z.a desc limit 6
  ) u;
  select count(*) filter (where a.status in ('checked_in','in_service')), count(*) filter (where a.status = 'upcoming')
    into pend, upc from appointments a where a.day = p_day;
  v_open := (f->>'opening')::numeric;
  return jsonb_build_object('figures', f, 'opening', v_open, 'expected_cash', expected_cash_of(f, v_open),
                            'big', big, 'pending', coalesce(pend,0), 'upcoming', coalesce(upc,0));
end $$;
revoke all on function public.close_day_preview(date) from public, anon;
grant execute on function public.close_day_preview(date) to authenticated;

create or replace function public.move_entry_day(p_kind text, p_id bigint, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_old date; v_ts timestamptz; s timestamptz; e timestamptz; v_closed timestamptz; v_new timestamptz;
begin
  if not is_owner() then raise exception 'النقل للمالك بس'; end if;
  if p_day is null or not exists (select 1 from business_days where day = p_day) then raise exception 'اليوم ده مش يوم عمل مسجّل'; end if;
  s := coalesce(p24b_start(p_day), p_day::timestamptz);
  select closed_at into v_closed from business_days where day = p_day;
  if p_kind = 'cash_move' then
    select day into v_old from cash_moves where id = p_id;
    if v_old is null then raise exception 'الحركة مش موجودة'; end if;
    update cash_moves set day = p_day where id = p_id;
  elsif p_kind = 'expense' then
    select spent_on into v_old from expenses where id = p_id and purchase_id is null;
    if v_old is null then raise exception 'المصروف مش موجود (أو تابع لمشتريات)'; end if;
    update expenses set spent_on = p_day where id = p_id;
  elsif p_kind = 'staff_tx' then
    select created_at into v_ts from staff_transactions where id = p_id;
    if v_ts is null then raise exception 'الحركة مش موجودة'; end if;
    select b.day into v_old from business_days b
     where coalesce(p24b_start(b.day), b.day::timestamptz) <= v_ts and v_ts <= coalesce(b.closed_at, 'infinity'::timestamptz)
     order by b.day desc limit 1;
    e := coalesce(v_closed, now());
    v_new := case when v_closed is not null then greatest(s + interval '1 second', e - interval '1 second') else now() end;
    update staff_transactions set created_at = v_new where id = p_id;
  else
    raise exception 'نوع غير معروف';
  end if;
  if v_old is not null and v_old <> p_day then perform p32_refresh_closing(v_old, 'move_entry_day: ' || p_kind || ' #' || p_id); end if;
  perform p32_refresh_closing(p_day, 'move_entry_day: ' || p_kind || ' #' || p_id);
  return jsonb_build_object('from', v_old, 'to', p_day);
end $$;
revoke all on function public.move_entry_day(text, bigint, date) from public, anon;
grant execute on function public.move_entry_day(text, bigint, date) to authenticated;

commit;
