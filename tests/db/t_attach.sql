\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
insert into customers(name) values ('عميل قديم');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
insert into invoices(customer_id,subtotal,discount,total,payment_method,created_at) values (null,100,0,100,'cash', now()-interval '30 days') returning id as inv \gset
select id as cid from customers where name='عميل قديم' \gset
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مينفعش', format('select invoice_attach_customer(%s,%s)',:inv,:cid));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select invoice_attach_customer(:inv,:cid) as r \gset
select t.ok('اتربطت', (select customer_id from invoices where id=:inv)=:cid);
select t.ok('نقاط اتحسبت', (select points from customers where id=:cid)=(:'r'::jsonb->>'points')::int and (:'r'::jsonb->>'points')::int>0);
select t.ok('زيارة +1', (select visits from customers where id=:cid)=1);
select t.ok('تاريخ النقاط = تاريخ الفاتورة', (select created_at from loyalty_ledger where invoice_id=:inv and reason='purchase') < now()-interval '29 days');
select t.fl('مرتين', format('select invoice_attach_customer(%s,%s)',:inv,:cid));
rollback;
\echo ATTACH DONE
