\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set c1 '00000000-0000-0000-0000-0000000000c1'
\i sql/patch_my_queue_phone.sql
begin;
update customers set phone='01012345678' where id=1;
insert into appointments(customer_id, barber_id, day, status, starts_at) values (1, :'b1', (now() at time zone my_tz())::date, 'upcoming', now());
select t.as_(:'b1');
select t.ok('الحلاق يشوف رقم عميله', (select count(*)>=1 and bool_or(phone='01012345678') from my_queue_phones()));
select t.as_(:'c1');
select t.ok('العميل مايشوفش حاجة', (select count(*)=0 from my_queue_phones()));
rollback;
\echo PHONE DONE
