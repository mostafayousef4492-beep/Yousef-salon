-- مكافأة/إيداع لموظف اتصرف كاش من الدرج: بتتسجل في حسابه + بتتخصم من الدرج.
-- المشكلة: «إيداع / مكافأة» بيزوّد رصيد الموظف بس، والدرج مابيتأثرش إلا بالسلف (سحب) وصرف الراتب.
-- فلو المدير سلّم المكافأة كاش وسجّلها بس، الدرج كان بيفضل زي ما هو.
-- الحل من غير ما نلمس دوال الدرج/القفل: staff_bonus_add بتسجّل المكافأة وبتسجّل معاها «صرف راتب» (من الدرج) بنفس المبلغ
-- في عملية واحدة. فرصيد الموظف مايتأثرش (اتدفعله فعلًا) والدرج بينزل بالمبلغ (sal_cash).
-- p_paid_now=false = السلوك القديم بالظبط (تتسجل في الحساب وتتصرف مع الراتب بعدين).
-- آمن للتكرار. مفيش بيانات بتتغير.
create or replace function public.staff_bonus_add(p_staff uuid, p_amount numeric, p_note text default null, p_paid_now boolean default false, p_on date default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_tx bigint; v_pay bigint; v_on date; v_at timestamptz; v_tz text := my_tz(); v_name text;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'اكتب مبلغ صحيح'; end if;
  select full_name into v_name from profiles where id = p_staff and role::text <> 'customer';
  if not found then raise exception 'الموظف غير موجود'; end if;
  v_on := coalesce(p_on, (now() at time zone v_tz)::date);
  if v_on > (now() at time zone v_tz)::date then raise exception 'التاريخ لسه ماجاش'; end if;
  v_at := case when p_on is null or p_on = (now() at time zone v_tz)::date then now() else (p_on::timestamp + interval '12 hours') at time zone v_tz end;
  insert into staff_transactions(staff_id, kind, amount, note, created_by, created_at)
    values (p_staff, 'bonus', round(p_amount, 2), nullif(trim(coalesce(p_note, '')), ''), auth.uid(), v_at) returning id into v_tx;
  if p_paid_now then
    insert into salary_payments(staff_id, period, amount, paid_on, paid_from, note, created_by, created_at)
      values (p_staff, date_trunc('month', v_on)::date, round(p_amount, 2), v_on, 'drawer',
              'صرف مكافأة' || coalesce(' — ' || nullif(trim(coalesce(p_note, '')), ''), ''), auth.uid(), v_at) returning id into v_pay;
  end if;
  return jsonb_build_object('tx_id', v_tx, 'payment_id', v_pay, 'paid_from_drawer', p_paid_now);
end $$;
revoke all on function public.staff_bonus_add(uuid, numeric, text, boolean, date) from public, anon;
grant execute on function public.staff_bonus_add(uuid, numeric, text, boolean, date) to authenticated;
