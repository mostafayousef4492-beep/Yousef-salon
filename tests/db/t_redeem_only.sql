\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set c1 '00000000-0000-0000-0000-0000000000c1'
\i sql/patch_redeem_services_only.sql
begin;
insert into services(id,name,price,duration_min,active) values (9001,'T-RD قص',70,30,true),(9002,'T-RD صبغة',500,30,true) on conflict (id) do nothing;
update services set redeemable = (id = 9001) where id in (9001,9002);
update customers set points = 1000 where user_id = :'c1';
select t.as_(:'c1');
select t.ok('الخدمة المسموحة بس في القايمة', (select count(*) from jsonb_array_elements(redeem_service_options()->'items') i where (i->>'id')::int in (9001,9002)) = 1);
select t.ok('الخدمة غير المسموحة مش في القايمة', not exists (select 1 from jsonb_array_elements(redeem_service_options()->'items') i where (i->>'id')::int = 9002));
select t.ok('استبدال خدمة مسموحة', (redeem_service(9001)->>'code') is not null);
select t.fl('رفض خدمة مش مسموحة', 'select redeem_service(9002)');
rollback;
