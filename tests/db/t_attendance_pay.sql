\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
-- موظفين تجربة: مساعد براتب 3000 (قديم), حلاق براتب 1500, حلاق بنسبة بس
insert into profiles(id,full_name,role,salary,commission_pct,created_at) values
 ('00000000-0000-0000-0000-0000000000c1','مساعد','assistant',3000,0,now()-interval '20 days'),
 ('00000000-0000-0000-0000-0000000000c2','حلاق براتب','barber',1500,0,now()-interval '20 days'),
 ('00000000-0000-0000-0000-0000000000c3','مدير','manager',6000,0,now()-interval '20 days')
 on conflict (id) do update set salary=excluded.salary, role=excluded.role, created_at=excluded.created_at;
update profiles set salary=0 where id in ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b2');
create temp table before_st as select jsonb_array_length(staff_statement('00000000-0000-0000-0000-0000000000c1')->'entries') n;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('الكاشف الأول فيه أيام راتب', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000c1')->'entries') e where e->>'kind'='salary')>=19);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
do $$ begin begin perform att_pay_all(); raise exception 'FAIL: غير المالك اشتغل'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end; end $$;
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select att_pay_all() as res \gset
reset role;
select t.ok('اتحول المساعد والحلاق براتب بس (2)', jsonb_array_length(:'res'::jsonb)=2);
select t.ok('المدير ماتحولش', not exists (select 1 from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000c3' and pay_mode='daily_attendance'));
select t.ok('اليومية = الراتب÷30', (select daily_wage from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000c1')=100 and (select daily_wage from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000c2')=50);
select t.ok('att_from = النهارده', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000c1')=(now() at time zone p11_tz())::date);
select t.ok('طريقة الخصم flat', (select method from late_rule where staff_id='00000000-0000-0000-0000-0000000000c1')='flat');
-- ما فيش حساب راتب لأيام بعد التحويل، واللي قبله فاضل
update staff_pay_profile set att_from=((now() at time zone p11_tz())::date - 5) where staff_id='00000000-0000-0000-0000-0000000000c1';
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('أيام الراتب بعد التحويل اتوقفت (الباقي قبل التحويل بس)',
  (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000c1')->'entries') e where e->>'kind'='salary')
  = (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000c2')->'entries') e where e->>'kind'='salary') - 5);
select t.ok('salary_part_for بيقص فترة الحضور',
  salary_part_for('00000000-0000-0000-0000-0000000000c1',3000, now()-interval '10 days', now()) = salary_part(3000, now()-interval '10 days', (now() at time zone p11_tz())::date::timestamp at time zone p11_tz() - interval '5 days'));
select t.ok('الموظف العادي زي ما هو', salary_part_for('00000000-0000-0000-0000-0000000000c2',1500, now()-interval '10 days', now()) = salary_part(1500, now()-interval '10 days', now()));
select t.ok('report_data بيشتغل ومرتبات أقل من غير الحضور', (report_data(now()-interval '10 days', now())->'totals'->>'salaries')::numeric
  = (select sum(salary_part_for(id, salary, now()-interval '10 days', now())) from profiles where role<>'owner' and salary>0));
select t.ok('full_report بيشتغل', full_report(now()-interval '10 days', now()) is not null);
reset role;
-- الحضور بينزل يومية والتأخير بيتخصم بعد 15
update staff_pay_profile set att_from=(now() at time zone p11_tz())::date where staff_id='00000000-0000-0000-0000-0000000000c1';
insert into attendance(staff_id,late_min) values ('00000000-0000-0000-0000-0000000000c1',15) returning id as a15 \gset
select t.ok('الحضور نزّل أجر يوم 100', (select count(*) from staff_transactions where staff_id='00000000-0000-0000-0000-0000000000c1' and note like 'أجر يوم%' and amount=100)=1);
select t.ok('15 دقيقة = سماح', not exists (select 1 from staff_transactions where kind='deduction' and note like '%[late#'||:a15||']%'));
update attendance set late_min=20 where id=:a15;
select t.ok('20 دقيقة = 20 جنيه', (select amount from staff_transactions where kind='deduction' and note like '%[late#'||:a15||']%')=20);
insert into attendance(staff_id,late_min,check_in) values ('00000000-0000-0000-0000-0000000000c2',40,now()-interval '1 day') returning id as a40 \gset
select t.ok('الحلاق براتب: 40 دقيقة = 40 جنيه', (select amount from staff_transactions where kind='deduction' and note like '%[late#'||:a40||']%')=40);
-- رجوع للشهري
select t.as_('00000000-0000-0000-0000-0000000000a1');
select set_daily_pay('00000000-0000-0000-0000-0000000000c1',100,12,10,false);
reset role;
select t.ok('رجوع للشهري بيحدد att_to', (select att_to from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000c1') is not null);
-- لو الموظف سجل حضور النهارده قبل التحويل، التحويل يبدأ من بكرة
insert into attendance(staff_id,late_min) values ('00000000-0000-0000-0000-0000000000a2',0);
update profiles set salary=900 where id='00000000-0000-0000-0000-0000000000a2';
select t.as_('00000000-0000-0000-0000-0000000000a1');
select set_daily_pay('00000000-0000-0000-0000-0000000000a2',30,12,600,true);
reset role;
select t.ok('حضر قبل التحويل = يبدأ من بكرة', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000a2')=(now() at time zone p11_tz())::date+1);
-- att_calc_late مع سماح 600
insert into staff_shifts(staff_id,weekday,start_time,end_time,is_off) values ('00000000-0000-0000-0000-0000000000c2',extract(dow from now() at time zone my_tz())::int,'09:00','21:00',false) on conflict do nothing;
update staff_pay_profile set late_grace_min=600 where staff_id='00000000-0000-0000-0000-0000000000c2';
select t.ok('att_calc_late: سماح 600 مش بيصفّر التأخير', att_calc_late('00000000-0000-0000-0000-0000000000c2', (date_trunc('day', now() at time zone my_tz()) + interval '9 hours 30 minutes') at time zone my_tz())=30);
rollback;
\echo ATTENDANCE PAY DONE
