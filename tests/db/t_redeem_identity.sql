\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\i sql/patch_fix_redeem_identity.sql
begin;
-- نفس وضع الإنتاج: id عمود identity ALWAYS (محلياً BY DEFAULT)
alter table loyalty_rewards alter column id set generated always;
update customers set user_id='00000000-0000-0000-0000-0000000000c1', points=300 where id=1;
update services set redeemable=true, redeem_points=100 where id=1;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',true);
set local role authenticated;
select (redeem_service(1)->>'code') is not null as got \gset
reset role;
select t.ok('الاستبدال نجح ورجّع كود', :'got'::boolean);
select t.ok('النقاط اتخصمت (300 → 200)', (select points = 200 from customers where id=1));
select t.ok('الكوبون اتسجّل', (select count(*)=1 from loyalty_redemptions r join loyalty_rewards w on w.id=r.reward_id where r.customer_id=1 and w.service_id=1 and r.status='active'));
rollback;
\echo RID DONE
