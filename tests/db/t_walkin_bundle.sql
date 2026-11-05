\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\i sql/patch_bundles.sql
\i sql/patch_walkin_bundles.sql
\i sql/patch_walkin_bundles.sql
begin;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select admin_save_bundle(null,'باقة عابر','',120,true,array[1,2]::bigint[]) as bid \gset
select admin_save_bundle(null,'باقة موقوفة','',100,false,array[1,2]::bigint[]) as hid \gset
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout_b(:bid, null, null, null, '[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb, 0, 0, 'cash') as inv \gset
select t.ok('عابر: خصم الباقة 30', (select subtotal=150 and discount=30 and total=120 from invoices where id=:inv));
select t.fl('عابر: خصم يدوي مع باقة', format($q$select pos_checkout_b(%s,null,null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,5,0,'cash')$q$,:bid));
select t.fl('عابر: باقة موقوفة', format($q$select pos_checkout_b(%s,null,null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash')$q$,:hid));
select pos_checkout_b(:bid, null, null, null, '[{"type":"service","id":1,"qty":1}]'::jsonb, 0, 0, 'cash') as inv2 \gset
select t.ok('عابر: ناقص خدمة = من غير خصم', (select discount=0 and total=100 from invoices where id=:inv2));
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash') as inv3 \gset
select t.ok('pos_checkout العادية بعدها من غير خصم (الإعداد اتصفّر)', (select discount=0 and total=150 from invoices where id=:inv3));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مايقفلش فاتورة', format($q$select pos_checkout_b(%s,null,null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash')$q$,:bid));
rollback;
\echo WALKIN DONE
