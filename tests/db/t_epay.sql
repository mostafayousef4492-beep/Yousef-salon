\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'wallet') as w1 \gset
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'wallet') as w2 \gset
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash') as c1 \gset
select t.ok('الرقم لسه مستخدمش', epay_ref_used('vodafone_cash','AB1234') is false);
select t.fl('فودافون من غير رقم عملية', format('select invoice_set_payment(%s,%L,%L)',:w1,'vodafone_cash',''));
select t.fl('رقم قصير', format('select invoice_set_payment(%s,%L,%L)',:w1,'instapay','12'));
select t.fl('قناة غلط', format('select invoice_set_payment(%s,%L,%L)',:w1,'paypal','123456'));
select t.fl('فاتورة كاش', format('select invoice_set_payment(%s,%L,%L)',:c1,'instapay','123456'));
select invoice_set_payment(:w1,'vodafone_cash','AB1234');
select t.ok('اتسجّلت', (select pay_channel='vodafone_cash' and pay_ref='AB1234' from invoices where id=:w1));
select t.ok('الرقم بقى مستخدم (حتى بحروف مختلفة)', epay_ref_used('vodafone_cash',' ab1234 ') is true);
select t.fl('نفس الرقم على فاتورة تانية', format('select invoice_set_payment(%s,%L,%L)',:w2,'vodafone_cash','ab1234'));
select invoice_set_payment(:w2,'instapay','AB1234');
select t.ok('نفس الرقم على قناة تانية مسموح', (select pay_channel='instapay' from invoices where id=:w2));
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'wallet') as w3 \gset
select invoice_set_payment(:w3,'other_wallet',null);
select t.ok('محفظة تانية من غير رقم', (select pay_channel='other_wallet' from invoices where id=:w3));
reset role;
update invoices set created_at=now()-interval '2 hours' where id=:w3;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('كاشير بعد 15 دقيقة', format('select invoice_set_payment(%s,%L,%L)',:w3,'instapay','ZZ9999'));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select invoice_set_payment(:w3,'instapay','ZZ9999');
select t.ok('المدير يعدّل', (select pay_ref='ZZ9999' from invoices where id=:w3));
reset role;
set local role anon;
select t.fl('الزائر مرفوض', $$select epay_ref_used('instapay','x')$$);
reset role;
rollback;
\echo EPAY DONE
