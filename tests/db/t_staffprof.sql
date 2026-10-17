\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): %', n; return; end; raise exception 'FAIL (should reject): %', n; end $$;
grant usage on schema t to public;
begin;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select set_staff_profile(null,'data:image/jpeg;base64,AAAA','1995-05-10');
select t.ok('الحلاق عدّل نفسه', (staff_profile()->>'birthday')='1995-05-10' and (staff_profile()->>'avatar') like 'data:image%');
select t.fl('حلاق يعدل زميله', $$select set_staff_profile('00000000-0000-0000-0000-0000000000b2','data:image/jpeg;base64,AAAA')$$);
select t.fl('حلاق يقرا زميله', $$select staff_profile('00000000-0000-0000-0000-0000000000b2')$$);
select t.fl('صورة مش صورة', $$select set_staff_profile(null,'javascript:alert(1)')$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select set_staff_profile('00000000-0000-0000-0000-0000000000b2',null,'1990-01-02');
select t.ok('المالك عدّل موظف', (staff_profile('00000000-0000-0000-0000-0000000000b2')->>'birthday')='1990-01-02');
select set_staff_profile('00000000-0000-0000-0000-0000000000b2',null,null,false,true);
select t.ok('مسح الميلاد', (staff_profile('00000000-0000-0000-0000-0000000000b2')->>'birthday') is null);
rollback;
\echo STAFFPROF DONE
