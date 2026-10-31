\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
begin;
delete from business_days; delete from cash_closings where day >= current_date - 10; delete from invoices where id >= 990300;
-- يوم 30 مقفول من غير جرد (حالة المستخدم) + يوم 31 مفتوح فاضي
insert into business_days(day, opened_at, closed_at) values (current_date - 1, now() - interval '30 hours', now() - interval '10 hours');
insert into business_days(day, opened_at) values (current_date, now() - interval '9 hours');
\i patch_reopen_day_v2.sql
select t.ok('الإصلاح: اليوم الفاضي اتشال واليوم القديم رجع مفتوح', (select count(*) from business_days where closed_at is null) = 1 and exists (select 1 from business_days where day = current_date - 1 and closed_at is null) and not exists (select 1 from business_days where day = current_date));
select t.ok('اتسجل في المحذوفات', exists (select 1 from deletion_log where table_name = 'business_days' and extra->>'reason' = 'repair_reopen_previous_day'));
-- تشغيل تاني ما يعملش حاجة
\i patch_reopen_day_v2.sql
select t.ok('تشغيل تاني آمن', (select count(*) from business_days) = 1);
-- reopen لما اليوم المفتوح فيه عمليات: يرفض
delete from business_days;
insert into business_days(day, opened_at, closed_at) values (current_date - 1, now() - interval '30 hours', now() - interval '10 hours');
insert into business_days(day, opened_at) values (current_date, now() - interval '9 hours');
insert into invoices(id,no,subtotal,total,payment_method,created_at) values (990301, 990301, 50, 50, 'cash', now() - interval '1 hour');
select t.as_(:'own');
select t.fl('يرفض لو اليوم المفتوح فيه فاتورة', 'select reopen_business_day()');
reset role;
delete from invoices where id = 990301;
select t.as_(:'own');
select reopen_business_day() as st \gset
reset role;
select t.ok('بعد ما فضي: reopen شال الفاضي ورجّع القديم', (:'st'::jsonb->>'open')::boolean and (:'st'::jsonb->>'day')::date = current_date - 1);
rollback;
\echo REOPEN V2 DONE
