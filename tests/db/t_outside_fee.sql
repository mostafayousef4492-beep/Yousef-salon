\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\i sql/patch_bundles.sql
\i sql/patch_walkin_bundles.sql
\i sql/patch_outside_fee.sql
\i sql/patch_outside_fee.sql
begin;
insert into app_settings(key,value) values ('outside_fee','200') on conflict (key) do update set value=excluded.value;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select admin_save_bundle(null,'باقة خارج','',120,true,array[1,2]::bigint[]) as bid \gset
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select pos_checkout_b(null,null,null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',null,null,null,false) as i1 \gset
select t.ok('داخل المحل: سعر الخدمات بس', (select total=150 from invoices where id=:i1));
select pos_checkout_b(null,null,null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',null,null,null,true) as i2 \gset
select t.ok('خارج المحل: +200', (select total=350 from invoices where id=:i2));
select t.ok('بند الخارج ظاهر', (select count(*)=1 from invoice_items where invoice_id=:i2 and name='خدمة خارج المحل' and unit_price=200));
select pos_checkout_b(:bid,null,null,null,'[{"type":"service","id":1,"qty":1},{"type":"service","id":2,"qty":1}]'::jsonb,0,0,'cash',null,null,null,true) as i3 \gset
select t.ok('باقة + خارج = سعر الباقة + 200', (select total=320 and discount=30 from invoices where id=:i3));
select pos_checkout(null,null,'[{"type":"service","id":1,"qty":1}]'::jsonb,0,0,'cash') as i4 \gset
select t.ok('pos_checkout العادية بعدها من غير رسوم', (select total=100 from invoices where id=:i4));
rollback;
\echo OUTSIDE DONE
