\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
begin;
\i sql/patch_edit_day.sql
\i sql/patch_staff_daily_due.sql
delete from business_days; delete from invoices where id >= 990600; delete from staff_transactions where note like 'T-DD%';
update profiles set commission_pct = 40, salary = 0, created_at = now() - interval '90 days' where id = :'b1';
insert into business_days(day, opened_at, closed_at) values (current_date-2, now()-interval '60 hours', now()-interval '40 hours'), (current_date-1, now()-interval '40 hours', now()-interval '16 hours');
insert into invoices(id,no,subtotal,total,payment_method,barber_id,created_at) values (990601,990601,100,100,'cash',:'b1', now()-interval '50 hours'),(990602,990602,200,200,'cash',:'b1', now()-interval '30 hours');
insert into staff_transactions(staff_id,kind,amount,note,created_at) values
 (:'b1','bonus',20,'T-DD مكافأة', now()-interval '49 hours'),
 (:'b1','advance',30,'T-DD سحب', now()-interval '29 hours'),
 (:'b1','deduction',10,'T-DD خصم', now()-interval '28 hours');
select closed_at as c2 from business_days where day=current_date-1 \gset
select p24b_start(current_date-2) as s1 \gset
select t.as_(:'own');
select t.ok('يومين لحلاق واحد على الأقل', (select count(*) from staff_daily_due(current_date-2, current_date-1) where staff_id=:'b1') = 2);
select t.ok('يوم 1: مكافأة 20', (select bonuses from staff_daily_due(current_date-2, current_date-2) where staff_id=:'b1') = 20);
select t.ok('يوم 2: سحب 30 وخصم 10', (select advances||'/'||deductions from staff_daily_due(current_date-1, current_date-1) where staff_id=:'b1') = '30.00/10.00' or (select advances=30 and deductions=10 from staff_daily_due(current_date-1, current_date-1) where staff_id=:'b1'));
select t.ok('مجموع الأيام = staff_summary للفترة', (select sum(net) from staff_daily_due(current_date-2, current_date-1) where staff_id=:'b1') = (select net from staff_summary(:'b1', :'s1'::timestamptz, :'c2'::timestamptz)));
select t.ok('الصافي = عمولة + مكافآت + راتب − سحب − خصومات', (select count(*) from staff_daily_due(current_date-2, current_date-1) x where x.net <> x.commission + x.bonuses + x.salary - x.advances - x.deductions) = 0);
select t.fl('أكتر من 62 يوم', $q$select * from staff_daily_due(current_date-100, current_date)$q$);
reset role;
select t.as_(:'cash');
select t.fl('الكاشير مايشوفش', $q$select * from staff_daily_due(current_date-2, current_date-1)$q$);
reset role;
rollback;
select 'STAFF DAILY DUE DONE';
