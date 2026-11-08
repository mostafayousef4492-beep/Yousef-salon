-- آلية واحدة بس للتأخير واليومية:
--   • اليومية بتنزل أول ما الموظف يسجّل حضور (زي ما هي).
--   • التأخير = «خصم الدقيقة» بعد فترة السماح (الإعدادات ← خصم التأخير) — ده الوحيد اللي بيخصم.
--   • إيقاف نهائي لخصم «الساعات الناقصة» (تأخير N ساعة) و«تسوية ساعات الشغل» اللي كانوا بيتخصموا فوق خصم الدقيقة
--     عن نفس الدقايق (مثلًا لما النظام يقفل الحضور الساعة 6 الصبح والموظف حاضر 11س و32د من 12).
-- مش بيمسح أو يعدّل أي حركة قديمة. آمن للتكرار.
begin;
create or replace function public.p12_recalc_day(p_staff uuid, p_day date)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare d assistant_day_pay%rowtype; tz text := p11_tz();
        v_open integer; v_worked integer; v_std integer; v_late integer;
        v_dh integer := 0; v_ded numeric := 0; v_note text; v_tx bigint;
begin
  select * into d from assistant_day_pay where staff_id = p_staff and day = p_day;
  if not found then return null; end if;

  select count(*) filter (where check_out is null),
         coalesce(round(sum(extract(epoch from (check_out - check_in))) filter (where check_out is not null) / 60.0), 0)::integer
    into v_open, v_worked
    from attendance
   where staff_id = p_staff and (check_in at time zone tz)::date = p_day;

  if v_open > 0 then
    update assistant_day_pay set worked_min = v_worked, closed = false, updated_at = now()
     where id = d.id;
    return jsonb_build_object('staff_id', p_staff, 'day', p_day, 'closed', false, 'worked_min', v_worked);
  end if;

  v_std  := round(d.standard_hours * 60)::integer;
  v_late := greatest(0, v_std - v_worked);
  /* p31: خصم الساعات الناقصة اتوقف — التأخير بالدقيقة بس (trg_late_deduct) */
  v_dh   := 0;
  v_ded  := least(d.wage, round(v_dh * d.wage / d.standard_hours, 2));
  v_note := 'تأخير ' || v_dh || ' ساعة (' || v_late || ' دقيقة أقل من ' || d.standard_hours || ' ساعة) ' || p_day;
  v_tx   := d.ded_tx_id;

  if v_ded > 0 then
    if v_tx is null then
      insert into staff_transactions(staff_id, kind, amount, note)
      values (p_staff, 'deduction', v_ded, v_note) returning id into v_tx;
    else
      update staff_transactions set amount = v_ded, note = v_note where id = v_tx;
    end if;
  elsif v_tx is not null then
    delete from staff_transactions where id = v_tx;
    v_tx := null;
  end if;

  update assistant_day_pay
     set worked_min = v_worked, late_min = v_late, deduct_hours = v_dh, deduction = v_ded,
         net_day = round(d.wage - v_ded, 2), closed = true, ded_tx_id = v_tx, updated_at = now()
   where id = d.id;

  return jsonb_build_object('staff_id', p_staff, 'day', p_day, 'closed', true, 'worked_min', v_worked,
                            'late_min', v_late, 'deduct_hours', v_dh, 'deduction', v_ded,
                            'net', round(d.wage - v_ded, 2));
end $$;

create or replace function public.adw_sync(p_staff uuid, p_day date)
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  pf staff_pay_profile%rowtype; r assistant_day_wage%rowtype; tz text := my_tz();
  v_n int; v_c int; v_h numeric := 0; v_rate numeric; v_ded numeric := 0; v_bon numeric := 0;
  v_amt numeric; v_kind text; v_tx bigint; v_id bigint;
begin
  if not exists (select 1 from profiles where id = p_staff and role = 'assistant') then return; end if;

  select count(*),
         count(*) filter (where check_out is not null),
         coalesce(sum(extract(epoch from (check_out - check_in)) / 3600.0) filter (where check_out is not null), 0)
    into v_n, v_c, v_h
    from attendance
   where staff_id = p_staff and (check_in at time zone tz)::date = p_day;

  select * into r from assistant_day_wage where staff_id = p_staff and day = p_day for update;

  if v_n = 0 then
    if found then
      delete from staff_transactions where id in (r.wage_tx, r.adj_tx);
      delete from assistant_day_wage where staff_id = p_staff and day = p_day;
    end if;
    return;
  end if;

  select * into pf from staff_pay_profile where staff_id = p_staff;
  if pf.staff_id is null or coalesce(pf.daily_wage, 0) <= 0 then return; end if;

  if r.staff_id is null then
    insert into staff_transactions(staff_id, kind, amount, note)
    values (p_staff, 'bonus', pf.daily_wage, 'أجر يوم ' || p_day) returning id into v_id;
    insert into assistant_day_wage(staff_id, day, wage, wage_tx) values (p_staff, p_day, pf.daily_wage, v_id);
    select * into r from assistant_day_wage where staff_id = p_staff and day = p_day;
  end if;

  if v_c = 0 or v_c <> v_n then return; end if;
  if coalesce(pf.standard_hours, 0) <= 0 then return; end if;
  /* p31: تسوية الساعات اتوقفت — اليومية بتنزل كاملة والتأخير بالدقيقة بس */
  return;

  v_h := round(v_h, 2);
  v_rate := r.wage / pf.standard_hours;
  if v_h < pf.standard_hours then
    v_ded := least(round((pf.standard_hours - v_h) * v_rate * coalesce(pf.deduct_rate, 100) / 100, 2), r.wage);
  elsif v_h > pf.standard_hours and coalesce(pf.bonus_rate, 0) > 0 then
    v_bon := round((v_h - pf.standard_hours) * v_rate * pf.bonus_rate / 100, 2);
  end if;

  v_amt := abs(v_bon - v_ded);
  v_kind := case when v_bon > v_ded then 'bonus' else 'deduction' end;
  v_tx := null;
  if v_amt > 0 then
    if r.adj_tx is not null then
      update staff_transactions
         set kind = v_kind, amount = v_amt,
             note = 'تسوية ساعات الشغل ' || p_day || ' (' || v_h || ' من ' || pf.standard_hours || ' ساعة)'
       where id = r.adj_tx returning id into v_tx;
    end if;
    if v_tx is null then
      insert into staff_transactions(staff_id, kind, amount, note)
      values (p_staff, v_kind, v_amt,
              'تسوية ساعات الشغل ' || p_day || ' (' || v_h || ' من ' || pf.standard_hours || ' ساعة)')
      returning id into v_tx;
    end if;
  elsif r.adj_tx is not null then
    delete from staff_transactions where id = r.adj_tx;
  end if;

  update assistant_day_wage
     set hours = v_h, bonus = v_bon, deduction = v_ded, adj_tx = v_tx, updated_at = now()
   where staff_id = p_staff and day = p_day;
end $$;
commit;
