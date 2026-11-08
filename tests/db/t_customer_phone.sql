\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin execute q; raise exception 'FAIL (no error): %', n; exception when others then if sqlerrm like 'FAIL%' then raise; end if; raise notice 'PASS: % [%]', n, sqlerrm; end $$;
grant usage on schema t to public;
\i sql/patch_customer_phone.sql
begin;
update customers set phone = '01011111111' where id = 1; update customers set phone = '01022222222' where id = 2;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
select admin_set_customer_phone(1, '01099999999');
select t.ok('تعديل رقم', (select phone from customers where id = 1) = '01099999999');
select t.ok('أرقام عربي', admin_set_customer_phone(1, '٠١٠٣٣٣٣٣٣٣٣') = '01033333333');
select t.fl('رقم عميل تاني مرفوض', $q$select admin_set_customer_phone(1, '01022222222')$q$);
select t.fl('رقم غلط مرفوض', $q$select admin_set_customer_phone(1, '123')$q$);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
select t.fl('حلاق مالوش صلاحية', $q$select admin_set_customer_phone(1, '01044444444')$q$);
rollback;
\echo CP DONE
