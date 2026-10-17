\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
insert into invoices(subtotal,discount,total,payment_method) values (100,0,100,'cash') returning id as inv \gset
insert into expenses(category,amount) values ('x',5) returning id as ex \gset
insert into staff_transactions(staff_id,kind,amount) values ('00000000-0000-0000-0000-0000000000b1','advance',10) returning id as tx \gset
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('غير المالك', format($$select admin_set_date('invoices',%s,current_date-2)$$,:inv));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select admin_set_date('invoices',:inv,current_date-5);
select t.ok('فاتورة اتنقلت', (select (created_at at time zone my_tz())::date from invoices where id=:inv)=(now() at time zone my_tz())::date-5);
select admin_set_date('expenses',:ex,current_date-5);
select t.ok('مصروف', (select spent_on from expenses where id=:ex)=(now() at time zone my_tz())::date-5);
select admin_set_date('staff_transactions',:tx,current_date-5);
select t.ok('سحب', (select (created_at at time zone my_tz())::date from staff_transactions where id=:tx)=(now() at time zone my_tz())::date-5);
select t.fl('مستقبل', format($$select admin_set_date('invoices',%s,current_date+3)$$,:inv));
select t.fl('جدول غلط', $$select admin_set_date('customers',1,current_date-1)$$);
reset role;
insert into cash_closings(day,opening,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet) select (now() at time zone my_tz())::date-8,0,0,0,0,0,0,0,0,0,0;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select (admin_set_date('invoices',:inv,current_date-8)->>'needs_force')::boolean as nf \gset
select t.ok('يوم مقفول يطلب تأكيد', :'nf'='t');
select t.ok('بالتأكيد يعدي', (admin_set_date('invoices',:inv,current_date-8,true)->>'saved')='true');
rollback;
\echo SETDATE DONE
