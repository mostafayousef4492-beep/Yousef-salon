\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000d1'),('00000000-0000-0000-0000-0000000000d2') on conflict do nothing;
insert into customers(name,phone) values ('بدون تاريخ','01099990001');
insert into customers(name,phone,points,visits) values ('له تاريخ','01099990002',50,3);
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('سجل كاشير بلا تاريخ → ربط فوري', register_customer('x','01099990001') > 0);
select t.ok('اتربط فعلًا', (select user_id::text from customers where phone='01099990001')='00000000-0000-0000-0000-0000000000d1');
reset role;
select t.as_('00000000-0000-0000-0000-0000000000d2');
select t.ok('سجل له تاريخ → طلب ربط (0)', register_customer('y','01099990002') = 0);
reset role;
select t.ok('طلب الربط اتسجل', exists(select 1 from claim_requests where user_id='00000000-0000-0000-0000-0000000000d2'));
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('الكاشير يشوف الطلبات', (select count(*) from pending_claims())=1);
select approve_claim((select id from pending_claims() limit 1));
reset role;
select t.ok('بعد الموافقة اتربط', (select user_id::text from customers where phone='01099990002')='00000000-0000-0000-0000-0000000000d2');
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('نفس الحساب تاني يرجع نفس السجل', register_customer('x','01099990001') > 0);
rollback;
\echo CLAIM TESTS DONE
