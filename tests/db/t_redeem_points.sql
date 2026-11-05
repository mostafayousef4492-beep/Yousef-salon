\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set c1 '00000000-0000-0000-0000-0000000000c1'
\i sql/patch_redeem_services_only.sql
\i sql/patch_redeem_points.sql
begin;
insert into services(id,name,price,duration_min,active) values (9101,'T-RP قص',70,30,true),(9102,'T-RP دقن',50,20,true) on conflict (id) do nothing;
update services set redeemable=true, redeem_points = case when id=9101 then 300 end where id in (9101,9102);
update customers set points = 350 where user_id = :'c1';
select t.as_(:'c1');
select t.ok('الخيارات فيها النقاط الثابتة', (select (i->>'use')::int = 300 and (i->>'pay')::numeric = 0 from jsonb_array_elements(redeem_service_options()->'items') i where (i->>'id')::int = 9101));
select t.ok('استبدال بنقاط ثابتة: الخدمة كاملة', (select (r->>'points_used')::int = 300 and (r->>'pay')::numeric = 0 from (select redeem_service(9101) r) x));
reset role;
select t.ok('اتخصم 300 بس', (select points from customers where user_id = :'c1') = 50);
select t.as_(:'c1');
select t.fl('نقاط ناقصة', 'select redeem_service(9101)');
rollback;
\echo REDEEM POINTS DONE
