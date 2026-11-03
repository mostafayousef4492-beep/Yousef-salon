-- "باقي له من الشهر القديم": متبقي الشهر اللي فات (المستحق − اللي اتصرف) لكل موظف، وزرار "صرف الراتب القديم" بيصرفه من الدرج.
-- الموظف يشوف رقمه هو (لو معاه صلاحية view_own_finance)، والمالك/المدير يشوف أي موظف ويصرف.
-- آمن للتشغيل أكتر من مرة.

create or replace function public.staff_old_month(p_staff uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_staff uuid := coalesce(p_staff, auth.uid()); v_tz text := my_tz(); v_cur date; v_prev date;
        v_due numeric := 0; v_paid numeric := 0; v_net numeric; v_role user_role;
begin
  if v_staff is null then return null; end if;
  if not (auth.uid() = v_staff or is_mgr()) then raise exception 'غير مصرح'; end if;
  select role into v_role from profiles where id = v_staff;
  if v_role is null or v_role in ('owner','customer') then return null; end if;
  if auth.uid() = v_staff and not is_mgr() and not has_perm('view_own_finance') then return null; end if;
  v_cur := date_trunc('month', biz_today())::date;
  v_prev := (v_cur - interval '1 month')::date;
  select s.net into v_net from staff_summary(v_staff, (v_prev::timestamp at time zone v_tz), (v_cur::timestamp at time zone v_tz)) s limit 1;
  v_due := coalesce(v_net, 0);
  select coalesce(sum(amount), 0) into v_paid from salary_payments where staff_id = v_staff and period = v_prev;
  return jsonb_build_object('period', v_prev, 'due', v_due, 'paid', v_paid, 'rem', greatest(0, v_due - v_paid));
end $$;

-- صرف المتبقي (أو جزء منه) من الدرج. مدير/مالك فقط.
create or replace function public.pay_old_salary(p_staff uuid, p_amount numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o jsonb; v_rem numeric; v_amt numeric; v_period date;
begin
  if not is_mgr() then raise exception 'غير مصرح'; end if;
  perform 1 from profiles where id = p_staff for update;   -- يمنع الصرف مرتين لو الزرار اتداس مرتين
  if not found then raise exception 'الموظف مش موجود'; end if;
  o := staff_old_month(p_staff);
  if o is null then raise exception 'مفيش راتب قديم للموظف ده'; end if;
  v_rem := (o->>'rem')::numeric; v_period := (o->>'period')::date;
  if v_rem <= 0 then raise exception 'مفيش متبقي من الشهر القديم'; end if;
  v_amt := coalesce(p_amount, v_rem);
  if v_amt <= 0 or v_amt > v_rem then raise exception 'المبلغ لازم يكون أكبر من صفر ومايزيدش عن المتبقي (%)', v_rem; end if;
  insert into salary_payments(staff_id, period, amount, paid_from, note, paid_on)
  values (p_staff, v_period, v_amt, 'drawer', 'صرف الراتب القديم', biz_today());
  return jsonb_build_object('paid', v_amt, 'rem', v_rem - v_amt, 'period', v_period);
end $$;

revoke all on function public.staff_old_month(uuid), public.pay_old_salary(uuid, numeric) from public, anon;
grant execute on function public.staff_old_month(uuid), public.pay_old_salary(uuid, numeric) to authenticated;
