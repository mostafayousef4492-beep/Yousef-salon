\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000d1'),('00000000-0000-0000-0000-0000000000d2'),('00000000-0000-0000-0000-0000000000d3') on conflict do nothing;
insert into profiles(id,full_name,role,salary,commission_pct,created_at) values
 ('00000000-0000-0000-0000-0000000000d1','مساعد أ','assistant',3100,0,now()-interval '15 days'),
 ('00000000-0000-0000-0000-0000000000d2','مساعد ب (من غير بروفايل)','assistant',3100,0,now()-interval '15 days'),
 ('00000000-0000-0000-0000-0000000000d3','حلاق عادي','barber',3100,0,now()-interval '15 days')
 on conflict (id) do update set salary=excluded.salary, role=excluded.role, created_at=excluded.created_at;
delete from staff_pay_profile where staff_id in ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000d3');
insert into staff_pay_profile(staff_id,pay_mode,daily_wage,att_from) values ('00000000-0000-0000-0000-0000000000d1','daily_attendance',100,current_date-2);
-- أ و ب: أجر يوم في يومين من أيام كان بيتحسب فيها راتب شهري
insert into staff_transactions(staff_id,kind,amount,note) select s, 'bonus', 100, 'أجر يوم '||d from (values ('00000000-0000-0000-0000-0000000000d1'::uuid),('00000000-0000-0000-0000-0000000000d2'::uuid)) a(s), (values ((current_date-9)::text),((current_date-8)::text)) b(d);
insert into staff_transactions(staff_id,kind,amount,note) values ('00000000-0000-0000-0000-0000000000d1','bonus',10,'مكافأة عادية');
\i patch_att_from_fix.sql
\i patch_att_from_fix.sql
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('أ: يوم فيه أجر يوم ماعليهوش راتب شهري', not exists (select 1 from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d1')->'entries') e where e->>'label' in ('راتب يوم '||(current_date-9),'راتب يوم '||(current_date-8))));
select t.ok('أ: يوم من غير أجر يوم لسه عليه راتب شهري', exists (select 1 from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d1')->'entries') e where e->>'label' = 'راتب يوم '||(current_date-6)));
select t.ok('ب (من غير بروفايل): نفس الشيء', not exists (select 1 from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d2')->'entries') e where e->>'label' = 'راتب يوم '||(current_date-9)));
select t.ok('الحلاق العادي كل أيامه راتب', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d3')->'entries') e where e->>'kind'='salary') >= 14);
select t.ok('أيام الأجور بس اتشالت: ب أقل من الحلاق بيومين', (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d2')->'entries') e where e->>'kind'='salary') = (select count(*) from jsonb_array_elements(staff_statement('00000000-0000-0000-0000-0000000000d3')->'entries') e where e->>'kind'='salary') - 2);
reset role;
select t.ok('p24_dup_days = 2', p24_dup_days('00000000-0000-0000-0000-0000000000d2', now()-interval '12 days', now()) = 2);
select t.ok('p24_dup_days لفترة مفيهاش الأيام دي = 0', p24_dup_days('00000000-0000-0000-0000-0000000000d2', now()-interval '5 days', now()) = 0);
select t.ok('salary_part_for ب = الراتب العادي − يومين',
  salary_part_for('00000000-0000-0000-0000-0000000000d2',3100, now()-interval '12 days', now())
  = salary_part(3100, now()-interval '12 days', now()) - round(3100 * 2 / extract(day from (date_trunc('month', now()-interval '12 days') + interval '1 month' - interval '1 day'))::numeric, 2));
select t.ok('salary_part_for للحلاق العادي ماتغيرش', salary_part_for('00000000-0000-0000-0000-0000000000d3',3100, now()-interval '12 days', now()) = salary_part(3100, now()-interval '12 days', now()));
select t.ok('مفيش حركة اتمسحت أو اتعدلت', (select count(*) from staff_transactions where staff_id='00000000-0000-0000-0000-0000000000d1')=3 and (select sum(amount) from staff_transactions where staff_id='00000000-0000-0000-0000-0000000000d1')=210);
select t.ok('report_data بيشتغل', (report_data(now()-interval '12 days', now())->'totals'->>'salaries') is not null);
select t.ok('full_report بيشتغل', (full_report(now()-interval '12 days', now())->>'salaries') is not null);
rollback;
select 'ATT FROM FIX DONE';
