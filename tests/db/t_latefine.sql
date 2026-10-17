\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
insert into attendance(staff_id,late_min,check_out) values ('00000000-0000-0000-0000-0000000000b1',15,now()) returning id as a15 \gset
select t.ok('15 دقيقة = سماح، مفيش خصم', (select count(*) from staff_transactions where attendance_id=:a15)=0);
insert into attendance(staff_id,late_min,check_out) values ('00000000-0000-0000-0000-0000000000b2',16,now()) returning id as a16 \gset
select t.ok('16 دقيقة = 16 جنيه', (select amount from staff_transactions where attendance_id=:a16 and kind='deduction')=16);
update attendance set late_min=30 where id=:a16;
select t.ok('30 دقيقة = 30 جنيه (بتتعدل مش بتتكرر)', (select amount from staff_transactions where attendance_id=:a16)=30 and (select count(*) from staff_transactions where attendance_id=:a16)=1);
update attendance set late_min=5 where id=:a16;
select t.ok('رجعت لسماح = اتشالت', (select count(*) from staff_transactions where attendance_id=:a16)=0);
update attendance set late_min=20 where id=:a16;
delete from attendance where id=:a16;
select t.ok('حذف الحضور بيحذف الغرامة', (select count(*) from staff_transactions where attendance_id=:a16)=0);
insert into app_settings(key,value) values ('late_fine_grace_min','10'::jsonb),('late_fine_per_min','2'::jsonb) on conflict (key) do update set value=excluded.value;
insert into attendance(staff_id,late_min,check_out) values ('00000000-0000-0000-0000-0000000000b2',11,now()) returning id as a11 \gset
select t.ok('سماح 10 وسعر 2: 11 دقيقة = 22', (select amount from staff_transactions where attendance_id=:a11)=22);
insert into app_settings(key,value) values ('late_fine_enabled','false'::jsonb) on conflict (key) do update set value=excluded.value;
insert into attendance(staff_id,late_min,check_out) values ('00000000-0000-0000-0000-0000000000b1',50,now()) returning id as aoff \gset
select t.ok('مقفول = مفيش خصم', (select count(*) from staff_transactions where attendance_id=:aoff)=0);
insert into attendance(staff_id,late_min,check_out) values ('00000000-0000-0000-0000-0000000000a1',60,now()) returning id as aown \gset
select t.ok('المالك مفيش خصم', (select count(*) from staff_transactions where attendance_id=:aown)=0);
rollback;
\echo LATEFINE DONE
