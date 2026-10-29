\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
delete from expenses where id in (20,16,12,17);
insert into expenses(id,spent_on,category,amount,note,paid_from) values (20,'2026-10-10','أخرى',4850,'راتب عزت','drawer'),(16,'2026-10-07','أخرى',1600,'راتب بوده','drawer'),(12,'2026-10-06','أخرى',1500,'راتب عبد الهادي','drawer'),(17,'2026-10-07','أخرى',1200,'راتب سامي','drawer'),(990020,'2026-10-08','أخرى',50,'شيء تاني','drawer');
insert into attendance(id,staff_id,check_in) values (990001,'00000000-0000-0000-0000-0000000000b1', now() - interval '30 hours'),(990002,'00000000-0000-0000-0000-0000000000b2', now() - interval '3 hours');
\i fix_cleanup_oct28.sql
select t.ok('الرواتب الأربعة اتنقلت لآخر سبتمبر', (select count(*)=4 and bool_and(spent_on='2026-09-30') from expenses where id in (20,16,12,17)));
select t.ok('المصروف التاني ما اتلمسش', (select spent_on='2026-10-08' from expenses where id=990020));
select t.ok('الحضور القديم اتقفل بعد 12 ساعة', (select check_out = check_in + interval '12 hours' from attendance where id=990001));
select t.ok('الحضور الحديث ما اتلمسش', (select check_out is null from attendance where id=990002));
\i fix_cleanup_oct28.sql
select t.ok('التشغيل التاني ما بيكررش الملاحظة', (select (length(note) - length(replace(note,'قبل تشغيل النظام',''))) / length('قبل تشغيل النظام') = 1 from expenses where id=20));
rollback;
