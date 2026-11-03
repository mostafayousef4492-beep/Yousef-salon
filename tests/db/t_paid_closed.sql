\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
begin;
\i sql/patch_edit_day.sql
\i sql/patch_paid_closed_day.sql
delete from business_days; delete from cash_closings where day >= current_date - 10; delete from invoices where id >= 990500;
insert into business_days(day, opened_at, closed_at) values (current_date-1, now()-interval '40 hours', now()-interval '16 hours');
insert into business_days(day, opened_at) values (current_date, now()-interval '16 hours');
insert into invoices(id,no,subtotal,total,payment_method,created_at,cashier_id) values (990501,990501,100,100,'cash', now()-interval '20 hours',:'cash'),(990502,990502,200,200,'cash', now()-interval '2 hours',:'cash');
insert into cash_closings(day,opening,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet,breakdown) values (current_date-1,0,100,0,0,100,0,0,0,0,0,'{}');
select t.as_(:'own');
select t.ok('يوم مقفول من غير تأكيد: يطلب تأكيد', (invoice_set_paid(990501,150)->>'needs_force')::boolean);
reset role;
select t.ok('ماتعدلتش', (select total from invoices where id=990501)=100);
select t.as_(:'own');
select t.ok('بتأكيد: يتعدل', (invoice_set_paid(990501,150,true)->>'refreshed_day')::date = current_date-1);
reset role;
select t.ok('الفاتورة 150', (select total from invoices where id=990501)=150);
select t.ok('قفلة اليوم اتحدثت المتوقع 150 والفرق -50', (select expected_cash from cash_closings where day=current_date-1)=150 and (select diff_cash from cash_closings where day=current_date-1)=-50);
select t.ok('القفلة القديمة اتسجلت', (select count(*) from deletion_log where extra->>'reason' like 'invoice_set_paid%')=1);
-- اليوم المفتوح: عادي بدون تأكيد
select t.as_(:'own');
select t.ok('يوم مفتوح عادي', (invoice_set_paid(990502,250)->>'paid')::numeric=250 and (invoice_set_paid(990502,250)->>'needs_force') is null);
select t.fl('أقل من المطلوب', $q$select invoice_set_paid(990502,100)$q$);
reset role;
select t.as_(:'cash');
select t.fl('الكاشير على يوم مقفول مرفوض', $q$select invoice_set_paid(990501,160,true)$q$);
reset role;
rollback;
select 'PAID CLOSED DONE';
