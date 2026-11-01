\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL (no error): %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
begin;
\i patch_edit_day.sql
delete from business_days; delete from cash_closings where day >= current_date - 10; delete from invoices where id >= 990400;
insert into business_days(day, opened_at, closed_at) values (current_date-2, now()-interval '60 hours', now()-interval '40 hours');
insert into business_days(day, opened_at, closed_at) values (current_date-1, now()-interval '40 hours', now()-interval '16 hours');
insert into business_days(day, opened_at) values (current_date, now()-interval '16 hours');
-- فاتورة بعد منتصف الليل: وقتها 20 ساعة قبل = جوه يوم (-1) المقفول
insert into invoices(id,no,subtotal,total,payment_method,created_at) values (990401,990401,100,100,'cash', now()-interval '20 hours'),(990402,990402,200,200,'cash', now()-interval '5 hours');
insert into cash_closings(day,opening,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet,breakdown) values (current_date-1,0,100,0,0,100,0,0,0,0,0,'{}');
select t.ok('قبل التعديل: يوم -1 فيه 100 كاش', (day_figures(current_date-1)->>'cash_sales')::numeric = 100);
select t.as_(:'own');
-- تأخير قفل يوم (-1) لحد ما يلم الفاتورة اللي وقتها 5 ساعات قبل (القفل قبل 2 ساعة) — والفاتورة 990402 كانت في اليوم المفتوح
select edit_business_day(current_date-1, null, now()-interval '2 hours');
reset role;
select t.ok('بعد التعديل: يوم -1 بقى فيه 300', (day_figures(current_date-1)->>'cash_sales')::numeric = 300);
select t.ok('الجرد اتحدّث المتوقع 300 والفرق -200', (select expected_cash from cash_closings where day=current_date-1)=300 and (select diff_cash from cash_closings where day=current_date-1)=-200);
select t.ok('اتسجل في المحذوفات', (select count(*) from deletion_log where extra->>'reason' like 'edit_business_day%') >= 2);
select t.as_(:'own');
select t.fl('قفل بعد قفل اللي بعده/المستقبل', $q$select edit_business_day(current_date-1, null, now()+interval '1 hour')$q$);
select t.fl('قفل قبل الفتح', $q$select edit_business_day(current_date-1, null, now()-interval '50 hours')$q$);
select t.fl('قفل قبل قفل اليوم اللي قبله', $q$select edit_business_day(current_date-1, null, now()-interval '41 hours')$q$);
select t.fl('يوم مفتوح: تعديل القفل مرفوض', $q$select edit_business_day(current_date, null, now())$q$);
select edit_business_day(current_date, now()-interval '15 hours', null);
reset role;
select t.ok('وقت فتح اليوم المفتوح اتعدّل', (select opened_at from business_days where day=current_date) > now()-interval '15 hours 1 minute');
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('غير المالك مرفوض', $q$select edit_business_day(current_date-1, null, now()-interval '3 hours')$q$);
rollback;
select 'ALL EDIT-DAY TESTS PASSED';
