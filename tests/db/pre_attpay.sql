-- نسخة محلية من اللي موجود على الإنتاج بخصوص الحضور واليومية (مأخوذة من الإنتاج قراءة فقط) — للاختبار المحلي بس
drop trigger if exists late_fine on attendance;
alter table staff_pay_profile add column if not exists pay_mode text not null default 'monthly';
alter table staff_pay_profile add column if not exists late_grace_min integer not null default 10;
do $$ begin if not exists (select 1 from pg_constraint where conrelid='staff_pay_profile'::regclass and contype='p') then alter table staff_pay_profile add primary key (staff_id); end if; end $$;
create table if not exists late_rule(staff_id uuid primary key, method text not null default 'flat', updated_at timestamptz default now());
create table if not exists assistant_day_pay(id bigserial primary key, staff_id uuid, day date, wage numeric, standard_hours numeric, grace_min integer, worked_min integer default 0, late_min integer default 0, deduct_hours integer default 0, deduction numeric default 0, net_day numeric, closed boolean default false, wage_tx_id bigint, ded_tx_id bigint, created_at timestamptz default now(), updated_at timestamptz default now(), unique(staff_id,day));
create or replace function p18_cfg(p_key text, p_def text) returns text language plpgsql stable security definer set search_path to 'public' as $$ declare v text; begin select trim(both '"' from value::text) into v from app_settings where key=p_key limit 1; return coalesce(nullif(v,''),p_def); exception when others then return p_def; end $$;
create or replace function p18_method(p_staff uuid) returns text language sql stable security definer set search_path to 'public' as $$ select coalesce((select method from late_rule where staff_id=p_staff), p18_cfg('late_default_method','flat')) $$;
create or replace function p18_kind_ok(k text) returns boolean language sql stable as $$ select true $$;
create or replace function set_daily_pay(p_staff uuid, p_wage numeric, p_hours numeric default 12, p_grace integer default 10, p_enabled boolean default true) returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if not is_owner() then raise exception 'غير مصرح'; end if;
  if not exists (select 1 from profiles where id=p_staff and role::text in ('assistant','barber','cashier')) then raise exception 'الموظف مش موجود'; end if;
  if p_enabled and (p_wage is null or p_wage<=0) then raise exception 'اكتب أجر يومي أكبر من صفر'; end if;
  insert into staff_pay_profile(staff_id,daily_wage,standard_hours,pay_mode,late_grace_min,adjust_by_attendance,updated_at)
  values (p_staff,coalesce(p_wage,0),p_hours,case when p_enabled then 'daily_attendance' else 'monthly' end,p_grace,false,now())
  on conflict (staff_id) do update set daily_wage=coalesce(p_wage,staff_pay_profile.daily_wage), standard_hours=p_hours,
    pay_mode=case when p_enabled then 'daily_attendance' else 'monthly' end, late_grace_min=p_grace, adjust_by_attendance=false, updated_at=now();
  return jsonb_build_object('staff_id',p_staff,'enabled',p_enabled);
end $$;
create or replace function p18_late_deduct() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_mark text; v_late int; v_grace numeric; v_rate numeric; v_on boolean; v_role text; v_id bigint; v_amt numeric;
begin
  if tg_op='DELETE' then delete from staff_transactions where kind='deduction' and note like '%[late#'||old.id::text||']%'; return old; end if;
  v_mark:='[late#'||new.id::text||']'; v_late:=coalesce(new.late_min,0);
  v_grace:=p18_cfg('late_grace_min','15')::numeric; v_rate:=p18_cfg('late_rate_per_min','1')::numeric; v_on:=p18_cfg('late_deduct_enabled','true')='true';
  select role into v_role from profiles where id=new.staff_id;
  if not v_on or v_role is null or v_role in ('owner','manager') or p18_method(new.staff_id)<>'flat' or v_late<=v_grace then
    delete from staff_transactions where kind='deduction' and note like '%'||v_mark||'%'; return new; end if;
  v_amt:=v_late*v_rate;
  select id into v_id from staff_transactions where kind='deduction' and note like '%'||v_mark||'%' limit 1;
  if v_id is not null then update staff_transactions set amount=v_amt, note='خصم تأخير '||v_late||' دقيقة '||v_mark where id=v_id;
  else insert into staff_transactions(staff_id,kind,amount,note,created_at) values (new.staff_id,'deduction',v_amt,'خصم تأخير '||v_late||' دقيقة '||v_mark,coalesce(new.check_in,now())); end if;
  return new;
end $$;
drop trigger if exists trg_late_deduct on attendance; drop trigger if exists trg_late_deduct_del on attendance;
create trigger trg_late_deduct after insert or update of late_min,check_in,staff_id on attendance for each row execute function p18_late_deduct();
create trigger trg_late_deduct_del after delete on attendance for each row execute function p18_late_deduct();
create or replace function p12_attendance_after_checkin()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare pf staff_pay_profile%rowtype; v_day date; v_row assistant_day_pay%rowtype; v_tx bigint;
begin
  begin
    select * into pf from staff_pay_profile where staff_id = NEW.staff_id;
    if not found or pf.pay_mode <> 'daily_attendance' or pf.daily_wage <= 0 then return NEW; end if;
    v_day := (NEW.check_in at time zone p11_tz())::date;

    select * into v_row from assistant_day_pay where staff_id = NEW.staff_id and day = v_day;
    if not found then
      insert into staff_transactions(staff_id, kind, amount, note)
      values (NEW.staff_id, 'bonus', pf.daily_wage, 'أجر يوم ' || v_day) returning id into v_tx;
      insert into assistant_day_pay(staff_id, day, wage, standard_hours, grace_min, net_day, wage_tx_id)
      values (NEW.staff_id, v_day, pf.daily_wage, pf.standard_hours, pf.late_grace_min, pf.daily_wage, v_tx);
    else
      if v_row.ded_tx_id is not null then delete from staff_transactions where id = v_row.ded_tx_id; end if;
      update assistant_day_pay
         set deduction = 0, deduct_hours = 0, late_min = 0, net_day = wage, closed = false,
             ded_tx_id = null, updated_at = now()
       where id = v_row.id;
    end if;

    if NEW.check_out is not null then
      perform p12_recalc_day(NEW.staff_id, v_day);
    end if;
  exception when others then
    raise warning 'p12 checkin: %', sqlerrm;
  end;
  return NEW;
end $function$;
drop trigger if exists zz_p12_attendance_checkin on attendance;
create trigger zz_p12_attendance_checkin after insert on attendance for each row execute function p12_attendance_after_checkin();
