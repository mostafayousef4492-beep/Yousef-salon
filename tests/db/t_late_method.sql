\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
create or replace function public.p12_deduct_hours(p_worked_min integer, p_std_min integer, p_grace integer) returns integer language sql immutable as $$
  select case when p_grace >= 600 then 0 when (p_std_min - p_worked_min) > p_grace then ceil((p_std_min - p_worked_min - p_grace) / 60.0)::integer else 0 end $$;
\i sql/patch_late_respect_method.sql
begin;
\set b1 '00000000-0000-0000-0000-0000000000b1'
update profiles set role = 'assistant' where id = :'b1';
delete from staff_pay_profile where staff_id = :'b1';
insert into staff_pay_profile(staff_id, daily_wage, standard_hours, adjust_by_attendance, deduct_rate, bonus_rate, pay_mode, late_grace_min)
values (:'b1', 100, 12, false, 100, 0, 'daily_attendance', 15);
-- حضور 6:28 م → 6:00 ص (11س 32د) في يوم فات
insert into attendance(staff_id, check_in, check_out) values (:'b1', date_trunc('day', now()) - interval '2 days' + interval '16 hours 28 min', date_trunc('day', now()) - interval '1 day' + interval '4 hours');
select (check_in at time zone p11_tz())::date as d from attendance where staff_id = :'b1' \gset
insert into assistant_day_pay(staff_id, day, wage, standard_hours, grace_min, net_day) values (:'b1', :'d', 100, 12, 15, 100) on conflict (staff_id, day) do nothing;

-- flat: مفيش خصم ساعات ولا تسوية
delete from late_rule where staff_id = :'b1'; insert into late_rule(staff_id, method) values (:'b1', 'flat');
select p12_recalc_day(:'b1', :'d'::date);
select adw_sync(:'b1', :'d'::date);
select t.ok('flat: مفيش خصم ساعات', (select deduction = 0 and ded_tx_id is null from assistant_day_pay where staff_id = :'b1' and day = :'d'));
select t.ok('flat: مفيش حركات خصم/تسوية', (select count(*) from staff_transactions where staff_id = :'b1' and (note like 'تسوية ساعات%' or note like 'تأخير %ساعة%')) = 0);
select t.ok('flat: الخصم صفر (اليومية كاملة)', (select net_day = 100 from assistant_day_pay where staff_id = :'b1' and day = :'d'));

-- باقي الطرق: برضه مفيش خصم ساعات ولا تسوية (آلية واحدة: خصم الدقيقة)
update late_rule set method = 'att' where staff_id = :'b1';
select p12_recalc_day(:'b1', :'d'::date);
select adw_sync(:'b1', :'d'::date);
select t.ok('att: مفيش خصم ساعات', (select deduction = 0 and deduct_hours = 0 from assistant_day_pay where staff_id = :'b1' and day = :'d'));
update late_rule set method = 'adj' where staff_id = :'b1';
select p12_recalc_day(:'b1', :'d'::date);
select adw_sync(:'b1', :'d'::date);
select t.ok('adj: مفيش تسوية ولا خصم', (select count(*) from staff_transactions where staff_id = :'b1' and (note like 'تسوية ساعات%' or note like 'تأخير %ساعة%')) = 0);
-- اليومية بتنزل أول حضور
delete from assistant_day_wage where staff_id = :'b1'; delete from staff_transactions where staff_id = :'b1';
select adw_sync(:'b1', :'d'::date);
select t.ok('اليومية 100 اتسجلت أول حضور', (select count(*) from staff_transactions where staff_id = :'b1' and kind = 'bonus' and amount = 100 and note like 'أجر يوم%') = 1);
select t.ok('ومفيش تسوية بعدها', (select count(*) from staff_transactions where staff_id = :'b1' and note like 'تسوية%') = 0);
rollback;
\echo LM DONE
