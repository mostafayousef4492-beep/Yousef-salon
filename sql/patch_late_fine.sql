-- غرامة التأخير التلقائية: بعد فترة السماح (الافتراضي 15 دقيقة) بيتخصم جنيه عن كل دقيقة تأخير
-- محسوبة من أول الميعاد (يعني عند الدقيقة 16 بيتخصم 16 جنيه وبعدها يزيد جنيه كل دقيقة).
-- بتتسجل كحركة "خصم" في حساب الموظف (مربوطة بسجل الحضور). لو سجل الحضور اتعدّل أو اتحذف الغرامة بتتعدّل/بتتحذف معاه.
-- التحكم من الإعدادات ← الموظفين: late_fine_enabled / late_fine_grace_min / late_fine_per_min
alter table public.staff_transactions add column if not exists attendance_id bigint references public.attendance(id) on delete cascade;
create unique index if not exists staff_tx_attendance_uq on public.staff_transactions(attendance_id) where attendance_id is not null;

create or replace function public.trg_late_fine()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_on boolean := p11_cfg_bool('late_fine_enabled', true); v_grace numeric := p11_cfg_num('late_fine_grace_min', 15);
        v_rate numeric := p11_cfg_num('late_fine_per_min', 1); v_fine numeric := 0; v_role text;
begin
  begin
    select role into v_role from profiles where id = new.staff_id;
    if v_on and v_role is not null and v_role <> 'owner' and coalesce(new.late_min,0) > v_grace then
      v_fine := round(new.late_min * v_rate, 2);
    end if;
    if v_fine > 0 then
      insert into staff_transactions(staff_id, kind, amount, note, created_at, attendance_id)
      values (new.staff_id, 'deduction', v_fine, 'غرامة تأخير ' || new.late_min || ' دقيقة (تلقائي)', new.check_in, new.id)
      on conflict (attendance_id) where attendance_id is not null
      do update set amount = excluded.amount, note = excluded.note, created_at = excluded.created_at;
    else
      delete from staff_transactions where attendance_id = new.id;
    end if;
  exception when others then
    raise warning 'late fine: %', sqlerrm;   -- ما نعطّلش تسجيل الحضور أبدًا
  end;
  return new;
end $$;
drop trigger if exists late_fine on public.attendance;
create trigger late_fine after insert or update of late_min, check_in on public.attendance
  for each row execute function public.trg_late_fine();

-- (اختياري) تطبيق الغرامة على فترة فاتت. المالك بس. مش بيتشغّل تلقائي.
create or replace function public.apply_late_fines(p_from date, p_to date)
returns int language plpgsql security definer set search_path to 'public' as $$
declare n int;
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then raise exception 'الفترة غير صحيحة (أقصى 3 شهور)'; end if;
  update attendance set late_min = late_min
   where (check_in at time zone my_tz())::date between p_from and p_to and late_min > 0;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.apply_late_fines(date,date) from public, anon;
grant execute on function public.apply_late_fines(date,date) to authenticated;
