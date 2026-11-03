\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set b2 '00000000-0000-0000-0000-0000000000b2'
-- مرتب ثابت 3000 + سحب 500 للحلاق b1 في الشهر اللي فات
update profiles set salary=3000, created_at = date_trunc('month', current_date) - interval '3 months' where id=:'b1';
update profiles set salary=3000, created_at = date_trunc('month', current_date) - interval '3 months' where id=:'b2';
insert into staff_transactions(staff_id,kind,amount,note,created_at) values (:'b1','advance',500,'سحب', date_trunc('month', now()) - interval '10 days');
select t.as_(:'own');
select t.ok('المالك يشوف المتبقي', (staff_old_month(:'b1')->>'due')::numeric = 2500 and (staff_old_month(:'b1')->>'rem')::numeric = 2500);
reset role;
-- الحلاق يشوف رقمه (بصلاحية view_own_finance)
update profiles set perms = coalesce(perms,'{}'::jsonb) || '{"view_own_finance":true}' where id=:'b1';
update profiles set perms = coalesce(perms,'{}'::jsonb) || '{"view_own_finance":false}' where id=:'b2';
select t.as_(:'b1');
select t.ok('الموظف يشوف بتاعه', (staff_old_month()->>'rem')::numeric = 2500);
select t.fl('مايشوفش موظف تاني', format('select staff_old_month(%L)', :'b2'));
select t.fl('الموظف مايصرفش', format('select pay_old_salary(%L)', :'b1'));
reset role;
select t.as_(:'b2');
select t.ok('من غير الصلاحية مفيش رقم', staff_old_month() is null);
reset role;
select t.as_(:'cash');
select t.fl('الكاشير مايصرفش', format('select pay_old_salary(%L)', :'b1'));
reset role;
-- المالك يصرف جزء ثم الباقي
select t.as_(:'own');
select t.fl('أكتر من المتبقي', format('select pay_old_salary(%L, 9999)', :'b1'));
select t.ok('صرف جزئي', (pay_old_salary(:'b1', 1000)->>'rem')::numeric = 1500);
select t.ok('المتبقي بعد الجزئي', (staff_old_month(:'b1')->>'rem')::numeric = 1500);
select t.ok('صرف الباقي', (pay_old_salary(:'b1')->>'paid')::numeric = 1500);
select t.fl('مفيش متبقي', format('select pay_old_salary(%L)', :'b1'));
select t.ok('صفر', (staff_old_month(:'b1')->>'rem')::numeric = 0);
reset role;
select t.ok('اتسجل من الدرج وبفترة الشهر اللي فات', (select count(*) from salary_payments where staff_id=:'b1' and paid_from='drawer' and note='صرف الراتب القديم' and period = (date_trunc('month', current_date) - interval '1 month')::date)=2);
rollback;
select 'OLD SALARY DONE';
