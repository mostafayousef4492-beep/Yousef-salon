\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000e1'),('00000000-0000-0000-0000-0000000000e2'),('00000000-0000-0000-0000-0000000000e3'),('00000000-0000-0000-0000-0000000000e4') on conflict do nothing;
insert into profiles(id,full_name,role,salary,commission_pct,created_at) values
 ('00000000-0000-0000-0000-0000000000e1','مساعد قديم','assistant',3000,0,now()-interval '12 days'),
 ('00000000-0000-0000-0000-0000000000e2','مساعد جديد','assistant',3000,0,now()-interval '12 days'),
 ('00000000-0000-0000-0000-0000000000e3','حلاق براتب','barber',1500,0,now()-interval '12 days'),
 ('00000000-0000-0000-0000-0000000000e4','مساعد شغال أجور قبل الإنشاء','assistant',3000,0,now()-interval '5 days')
 on conflict (id) do update set salary=excluded.salary, role=excluded.role, created_at=excluded.created_at;
delete from staff_pay_profile where staff_id in ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000e4');
-- قديم: اتحول من يومين (الوضع الغلط: راتب شهري قبله)
insert into staff_pay_profile(staff_id,pay_mode,daily_wage,att_from) values ('00000000-0000-0000-0000-0000000000e1','daily_attendance',100,current_date-2);
insert into staff_pay_profile(staff_id,pay_mode,daily_wage,att_from) values ('00000000-0000-0000-0000-0000000000e4','daily_attendance',100,current_date-1);
insert into staff_pay_profile(staff_id,pay_mode,daily_wage,att_from) values ('00000000-0000-0000-0000-0000000000e3','monthly',0,null);
insert into staff_transactions(staff_id,kind,amount,note,created_at) values
 ('00000000-0000-0000-0000-0000000000e1','bonus',100,'أجر يوم '||(current_date-9), now()-interval '1 hour'),
 ('00000000-0000-0000-0000-0000000000e4','bonus',100,'أجر يوم '||(current_date-8), now()-interval '1 hour');
select t.as_('00000000-0000-0000-0000-0000000000a1');
create temp table b4 as select count(*) n from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000e1')->'entries') x where x->>'kind'='salary';
reset role;
select t.ok('قبل: فيه راتب شهري لأيام مفيهاش حضور', (select n from b4) >= 8);
\i patch_pay_by_days.sql
\i patch_pay_by_days.sql
select t.ok('القديم: att_from رجع لأول يوم (إنشاء الحساب أو أول أجر)', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000e1') = (select least((created_at at time zone p11_tz())::date, current_date-9) from profiles where id='00000000-0000-0000-0000-0000000000e1'));
select t.ok('اللي أجره قبل الإنشاء: att_from لأول أجر', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000e4') = current_date-8);
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('مفيش راتب شهري تاني للمساعد القديم', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000e1')->'entries') x where x->>'kind'='salary') = 0);
select t.ok('أجر اليوم لسه موجود في كشفه', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000e1')->'entries') x where x->>'kind'='wage') = 1);
select t.ok('الحلاق الشهري ماتأثرش (فيه راتب)', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000e3')->'entries') x where x->>'kind'='salary') >= 10);
reset role;
select t.ok('راتب الفترة للمساعد = 0 من غير أجور', salary_part_for('00000000-0000-0000-0000-0000000000e1',3000, now()-interval '12 days', now()) = 0);
select t.ok('الحلاق الشهري راتبه زي ما هو', salary_part_for('00000000-0000-0000-0000-0000000000e3',1500, now()-interval '12 days', now()) = salary_part(1500, now()-interval '12 days', now()));
-- مساعد جديد بيتحول من الأول: التريجر
insert into staff_pay_profile(staff_id,pay_mode,daily_wage) values ('00000000-0000-0000-0000-0000000000e2','daily_attendance',100);
select t.ok('تحويل مساعد جديد: att_from = أول يوم له مش النهارده', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000e2') = (select (created_at at time zone p11_tz())::date from profiles where id='00000000-0000-0000-0000-0000000000e2'));
delete from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000e3';
insert into staff_pay_profile(staff_id,pay_mode,daily_wage) values ('00000000-0000-0000-0000-0000000000e3','daily_attendance',100);
select t.ok('الحلاق (مش مساعد): بيبدأ من يوم التحويل زي الأول', (select att_from from staff_pay_profile where staff_id='00000000-0000-0000-0000-0000000000e3') >= current_date);
select t.ok('مفيش حركة اتمسحت', (select count(*) from staff_transactions where staff_id in ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e4'))=2);
rollback;
select 'PAY BY DAYS DONE';
