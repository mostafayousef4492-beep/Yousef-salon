\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
begin;
-- Saturday(6) 14:00->02:00 for barber b1 ; day 2026-10-17 is Saturday
insert into staff_shifts(staff_id,weekday,is_off,start_time,end_time) values ('00000000-0000-0000-0000-0000000000b1',6,false,'14:00','02:00')
 on conflict (staff_id,weekday) do update set is_off=false,start_time='14:00',end_time='02:00';
select t.ok('السبت 20:00 متاح', (select count(*) from barber_hours('2026-10-17') h where h.barber_id='00000000-0000-0000-0000-0000000000b1' and '20:00'::time>=h.start_time and '20:00'::time<h.end_time)=1);
select t.ok('الأحد 01:00 متاح (ذيل السبت)', (select count(*) from barber_spill('2026-10-18') where barber_id='00000000-0000-0000-0000-0000000000b1' and '01:00'::time<spill_end)=1);
select t.ok('الأحد 03:00 مش متاح', (select count(*) from barber_spill('2026-10-18') where barber_id='00000000-0000-0000-0000-0000000000b1' and '03:00'::time<spill_end)=0);
select t.ok('الليل في available_barbers الأحد', exists(select 1 from available_barbers('2026-10-18','night') where id='00000000-0000-0000-0000-0000000000b1'));
select t.ok('السبت المسا available', exists(select 1 from available_barbers('2026-10-17','evening') where id='00000000-0000-0000-0000-0000000000b1'));
-- name-only customers
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('إضافة بالاسم بس', (select add_customer('أحمد بالاسم',null))>0);
reset role;
select t.ok('phone null', (select phone from customers where name='أحمد بالاسم') is null);
update customers set points=40,lifetime_points=60,visits=2 where name='أحمد بالاسم';
select t.as_('00000000-0000-0000-0000-0000000000a2');
select attach_customer_phone((select id from customers where name='أحمد بالاسم'),'01011112222');
reset role;
select t.ok('ربط برقم جديد: نفس السجل بالنقاط', (select points from customers where phone='01011112222')=40);
-- merge case
insert into customers(name,phone,points,lifetime_points,visits) values ('قديم','01033334444',10,10,1);
insert into customers(name,points,lifetime_points,visits) values ('اسم بس تاني',25,25,3);
select t.as_('00000000-0000-0000-0000-0000000000a2');
select attach_customer_phone((select id from customers where name='اسم بس تاني'),'01033334444');
reset role;
select t.ok('دمج: النقاط اتجمعت', (select points from customers where phone='01033334444')=35);
select t.ok('دمج: الزيارات', (select visits from customers where phone='01033334444')=4);
select t.ok('دمج: السجل اتمسح', not exists(select 1 from customers where name='اسم بس تاني'));
select t.as_('00000000-0000-0000-0000-0000000000b1');
do $$ begin begin perform add_customer('x y',null); raise exception 'bad'; exception when others then if sqlerrm='bad' then raise; end if; end; end $$;
rollback;
\echo OVERNIGHT/NAMEONLY TESTS DONE
