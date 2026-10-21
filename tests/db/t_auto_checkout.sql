\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\set b2 '00000000-0000-0000-0000-0000000000b2'
\set c2 '00000000-0000-0000-0000-0000000000c2'
\set d3 '00000000-0000-0000-0000-0000000000d3'
\set d5 '00000000-0000-0000-0000-0000000000d5'
\set d6 '00000000-0000-0000-0000-0000000000d6'
insert into auth.users(id) values (:'c2'),(:'d3'),(:'d5'),(:'d6') on conflict do nothing;
insert into profiles(id,full_name,role,salary,created_at) values (:'c2','ب','barber',0,now()-interval '20 days'),(:'d3','ج','barber',0,now()-interval '20 days'),(:'d5','هـ','barber',0,now()-interval '20 days'),(:'d6','و','barber',0,now()-interval '20 days') on conflict (id) do nothing;
create temp table dd as select (now() at time zone my_tz())::date - 3 d;
delete from staff_shifts where staff_id in (:'b1',:'b2',:'d3',:'d5',:'d6');
-- b1: شيفت نهاري 08-17 كل الأيام. b2: ليلي 18-06. c2: مفيش شيفت
insert into staff_shifts(staff_id,weekday,start_time,end_time,is_off) select :'b1', w, '08:00','17:00', false from generate_series(0,6) w;
insert into staff_shifts(staff_id,weekday,start_time,end_time,is_off) select x, w, '18:00','06:00', false from generate_series(0,6) w, unnest(array[:'b2'::uuid,:'d3'::uuid]) x;
insert into staff_shifts(staff_id,weekday,start_time,end_time,is_off) select :'d5', w, '08:00','17:00', false from generate_series(0,6) w;
insert into staff_shifts(staff_id,weekday,start_time,end_time,is_off) select :'d6', w, '08:00','17:00', false from generate_series(0,6) w;
-- 1) نهاري نسي الانصراف
insert into attendance(staff_id,late_min,check_in) select :'b1',0,((select d from dd)+time '09:00') at time zone my_tz() returning id as a1 \gset
-- 2) ليلي حضر 19:00 ونسي
insert into attendance(staff_id,late_min,check_in) select :'b2',0,((select d from dd)+time '19:00') at time zone my_tz() returning id as a2 \gset
-- 3) ليلي حضر بعد نص الليل 02:00 (شيفت إمبارح)
insert into attendance(staff_id,late_min,check_in) select :'d3',0,((select d from dd)+1+time '02:00') at time zone my_tz() returning id as a3 \gset
-- 4) من غير شيفت
insert into attendance(staff_id,late_min,check_in) select :'c2',0,((select d from dd)+time '09:00') at time zone my_tz() returning id as a4 \gset
-- 5) نهاري حضر بعد نهاية الشيفت 18:00
insert into attendance(staff_id,late_min,check_in) select :'d5',0,((select d from dd)+1+time '18:00') at time zone my_tz() returning id as a5 \gset
select p21_auto_checkout() as n \gset
select t.ok('اتقفل 3 تسجيلات', :n=3);
select t.ok('النهاري اتقفل 17:00 بالظبط', (select check_out at time zone my_tz() from attendance where id=:a1)=((select d from dd)+time '17:00'));
select t.ok('الليلي اتقفل 06:00 تاني يوم', (select check_out at time zone my_tz() from attendance where id=:a2)=((select d from dd)+1+time '06:00'));
select t.ok('اللي حضر 02:00 اتقفل 06:00', (select check_out at time zone my_tz() from attendance where id=:a3)=((select d from dd)+1+time '06:00'));
select t.ok('من غير شيفت فضل مفتوح', (select check_out is null from attendance where id=:a4));
select t.ok('حضر بعد نهاية الشيفت فضل مفتوح', (select check_out is null from attendance where id=:a5));
select t.ok('الملاحظة اتكتبت', (select note like '%انصراف تلقائي%' from attendance where id=:a1));
select t.ok('تاني مرة ماعملش حاجة', p21_auto_checkout()=0);
-- يوم إجازة
update staff_shifts set is_off=true where staff_id=:'d6' and weekday=extract(dow from (select d from dd)+2)::int;
insert into attendance(staff_id,late_min,check_in) select :'d6',0,((select d from dd)+2+time '09:00') at time zone my_tz() returning id as a6 \gset
select p21_auto_checkout();
select t.ok('يوم إجازة فضل مفتوح', (select check_out is null from attendance where id=:a6));
-- الإعداد مقفول
update app_settings set value='false'::jsonb where key='auto_checkout_enabled';
update staff_shifts set is_off=false where staff_id=:'d6';
select t.ok('الإعداد مقفول = مفيش حاجة', p21_auto_checkout()=0 and (select check_out is null from attendance where id=:a6));
rollback;
\echo AUTO CHECKOUT DONE
