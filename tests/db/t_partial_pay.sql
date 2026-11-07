\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin execute q; raise exception 'FAIL (no error): %', n; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: % [%]', n, sqlerrm; end $$;
grant usage on schema t to public;
\i sql/patch_partial_pay.sql
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
insert into invoices(customer_id, barber_id, subtotal, discount, total, payment_method) values (1, '00000000-0000-0000-0000-0000000000b1', 200, 0, 200, 'cash') returning id as i1 \gset
insert into invoices(customer_id, barber_id, subtotal, discount, total, payment_method) values (null, '00000000-0000-0000-0000-0000000000b1', 100, 0, 100, 'cash') returning id as i2 \gset
set local role authenticated;
select t.fl('الباقي = الإجمالي مرفوض', format('select invoice_set_unpaid(%s, 200)', :i1));
select t.fl('صفر مرفوض', format('select invoice_set_unpaid(%s, 0)', :i1));
select t.fl('زبون عابر من غير اسم مرفوض', format('select invoice_set_unpaid(%s, 40)', :i2));
select invoice_set_unpaid(:i1, 80);
select t.ok('total بقى 120 و unpaid 80', (select total = 120 and unpaid = 80 from invoices where id = :i1));
select t.fl('مرتين مرفوض', format('select invoice_set_unpaid(%s, 10)', :i1));
select invoice_set_unpaid(:i2, 40, 'أحمد عابر', '010-1234-5678');
select t.ok('دين زبون بدون ملف: اسم ورقم', (select debtor_name = 'أحمد عابر' and debtor_phone = '01012345678' from invoices where id = :i2));
select t.ok('قايمة الديون فيها الاتنين', (select count(*) from debts_list()) = 2);
select t.ok('فلتر الزبون 1', (select count(*) from debts_list(1)) = 1 and (select remaining from debts_list(1)) = 80);
select t.fl('سداد أكتر من المتبقي مرفوض', format('select debt_collect(%s, 81)', :i1));
select debt_collect(:i1, 30, 'cash') as s1 \gset
select t.ok('فاتورة السداد: total 30، بنفس الحلاق، ليها الأصل', (select total = 30 and barber_id = '00000000-0000-0000-0000-0000000000b1' and settles_invoice = :i1 and customer_id = 1 from invoices where id = :s1));
select t.ok('المتبقي 50', (select remaining from debts_list(1)) = 50);
select debt_collect(:i1, 50, 'wallet');
select t.ok('اتسدد كله: الدين اختفى', (select count(*) from debts_list(1)) = 0);
select t.ok('الأصل unpaid لسه 80 (تاريخ)', (select unpaid from invoices where id = :i1) = 80);
select t.ok('مجموع المبيعات للزبون = 200', (select sum(total) from invoices where id = :i1 or settles_invoice = :i1) = 200);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
select t.fl('حلاق عادي مالوش صلاحية', 'select debts_list()');
rollback;
\echo PP DONE
