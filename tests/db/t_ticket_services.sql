\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_ticket_services.sql
begin;
insert into appointments(customer_id, barber_id, day, status, starts_at) values (1, :'b1', current_date, 'upcoming', now()) returning id as aid \gset
set local role anon;
select set_ticket_services(:aid, array[1,2]::bigint[], '01000000001');
reset role;
select t.ok('الخدمات اتسجلت', (select count(*)=2 from appointment_services where appointment_id=:aid));
set local role anon;
select set_ticket_services(:aid, array[1]::bigint[], '01000000001');
reset role;
select t.ok('التغيير بيستبدل', (select count(*)=1 from appointment_services where appointment_id=:aid));
set local role anon;
select t.fl('رقم غلط', format('select set_ticket_services(%s, array[1]::bigint[], ''01999999999'')', :aid));
select t.fl('من غير خدمات', format('select set_ticket_services(%s, array[]::bigint[], ''01000000001'')', :aid));
reset role;
update appointments set status='checked_in' where id=:aid; update appointments set status='in_service' where id=:aid;
set local role anon;
select t.fl('بعد البدء ممنوع', format('select set_ticket_services(%s, array[2]::bigint[], ''01000000001'')', :aid));
rollback;
\echo TSVC DONE
