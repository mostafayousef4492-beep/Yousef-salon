\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
\set own '00000000-0000-0000-0000-0000000000a1'
\set a1 '00000000-0000-0000-0000-0000000000e1'
insert into auth.users(id) values (:'a1') on conflict do nothing;
insert into profiles(id,full_name,role,salary,created_at) values (:'a1','مساعد','assistant',0,now()-interval '10 days') on conflict (id) do nothing;
insert into staff_transactions(staff_id,kind,amount,note) values
 (:'a1','bonus',70,'أجر يوم 2026-10-01'),(:'a1','bonus',70,'أجر يوم 2026-10-02'),
 (:'a1','bonus',25,'مكافأة حقيقية'),(:'a1','deduction',20,'خصم تأخير 20 دقيقة [late#1]'),(:'a1','advance',30,'سلفة');
select t.as_(:'own');
create temp table sm as select * from staff_summary(:'a1', now()-interval '30 days', now()+interval '1 day');
select t.ok('الأجر اليومي في الراتب = 140', (select salary from sm)=140);
select t.ok('المكافآت = 25 بس', (select bonuses from sm)=25);
select t.ok('الخصم = 20 والسحب = 30', (select deductions from sm)=20 and (select advances from sm)=30);
select t.ok('الصافي ثابت = 140+25-30-20', (select net from sm)=115);
select t.ok('التقرير الشامل: راتب 140 ومكافآت 25', (select (e->>'salary')::numeric=140 and (e->>'bonus')::numeric=25 and (e->>'deduction')::numeric=20 and (e->>'cost')::numeric=145
  from jsonb_array_elements(full_report(now()-interval '30 days', now()+interval '1 day')->'staff') e where e->>'id'=:'a1'));
select t.ok('تقرير الفترة: الرواتب فيها الأجر والمكافآت من غيره', (report_data(now()-interval '30 days', now()+interval '1 day')->'totals'->>'bonuses')::numeric=25
  and (report_data(now()-interval '30 days', now()+interval '1 day')->'totals'->>'salaries')::numeric>=140);
rollback;
\echo WAGE SALARY DONE
