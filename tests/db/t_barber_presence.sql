\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set b2 '00000000-0000-0000-0000-0000000000b2'
create temp table today as select (now() at time zone my_tz())::date d;
select t.ok('من غير حضور: محدش ظاهر النهارده', (select count(*) from available_barbers((select d from today),'morning'))=0);
select t.ok('الأيام الجاية مش متأثرة', (select count(*) from available_barbers((select d from today)+1,'morning'))=2);
insert into attendance(staff_id,late_min) values (:'b1',0) returning id as a1 \gset
select t.ok('b1 سجل حضور = ظهر هو بس', (select array_agg(id) from available_barbers((select d from today),'morning'))=array[:'b1'::uuid]);
update attendance set check_out=now() where id=:a1;
select t.ok('b1 سجل انصراف = اختفى', (select count(*) from available_barbers((select d from today),'morning'))=0);
insert into attendance(staff_id,late_min,check_in) values (:'b2',0,now()-interval '30 hours');
select t.ok('حضور مفتوح من أكتر من 20 ساعة مش بيحسب', (select count(*) from available_barbers((select d from today),'morning'))=0);
update app_settings set value='false'::jsonb where key='booking_require_checkin';
select t.ok('لو الإعداد مقفول = الجدول العادي', (select count(*) from available_barbers((select d from today),'morning'))=2);
delete from app_settings where key='booking_require_checkin';
select t.ok('من غير إعداد = شغّال (محدش ظاهر)', (select count(*) from available_barbers((select d from today),'morning'))=0);
rollback;
\echo PRESENCE DONE
