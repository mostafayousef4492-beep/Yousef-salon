\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
delete from cash_closings where day >= '2026-10-20'; delete from business_days; delete from invoices where id between 991000 and 991099;
delete from cash_moves where day >= '2026-10-20'; delete from expenses where spent_on >= '2026-10-20'; delete from staff_transactions where created_at >= '2026-10-20';
insert into business_days(day,opened_at,closed_at) values ('2026-10-24','2026-10-23 21:00+00','2026-10-25 05:41+00'),('2026-10-25','2026-10-25 15:29+00',null);
insert into invoices(id,no,subtotal,total,payment_method,created_at) values
 (991001,991001,270,270,'cash','2026-10-25 12:00+03'),(991002,991002,150,150,'wallet','2026-10-25 13:00+03'),
 (991003,991003,720,720,'cash','2026-10-26 16:00+03'),(991004,991004,220,220,'wallet','2026-10-26 17:00+03'),
 (991005,991005,500,500,'cash','2026-10-25 03:00+03');   -- قبل قفل يوم 24: مش بتاعتنا
insert into expenses(spent_on,category,amount,paid_from,created_at) values ('2026-10-25','x',210,'drawer','2026-10-25 20:00+03'),('2026-10-25','x',230,'drawer','2026-10-26 04:39+03');
insert into cash_moves(day,kind,amount,created_at) values ('2026-10-25','deposit',100,'2026-10-26 04:44+03'),('2026-10-25','withdraw',1500,'2026-10-26 23:29+03');
insert into staff_transactions(staff_id,kind,amount,created_at) select id,'advance',v.a,v.t::timestamptz from (select id from profiles limit 1) p, (values (1030,'2026-10-25 18:00+03'),(450,'2026-10-26 18:00+03')) v(a,t);
\i fix_close_25_26.sql
select t.ok('يوم 25: افتتاح 4060', (select opening from cash_closings where day='2026-10-25')=4060);
select t.ok('يوم 25: آخره 3090 وفرق صفر', (select counted_cash=3090 and diff_cash=0 from cash_closings where day='2026-10-25'));
select t.ok('يوم 26: افتتاحه 3090 وآخره 1730 وفرق صفر', (select opening=3090 and counted_cash=1730 and diff_cash=0 and diff_wallet=0 from cash_closings where day='2026-10-26'));
select t.ok('يوم 27 مفتوح ويوم 25 و26 مقفولين', (select count(*) from business_days where closed_at is null and day='2026-10-27')=1 and (select count(*) from business_days where closed_at is not null and day>='2026-10-25')=2);
select t.ok('فاتورة 26 في يوم 26', (select (day_figures('2026-10-26')->>'invoices')::int from (select 1) x)=2 and (day_figures('2026-10-25')->>'invoices')::int=2);
select t.ok('يوم 27 بيبدأ بافتتاح 1730', (day_figures('2026-10-27')->>'opening')::numeric=1730);
select t.ok('يوم 27 فاضي', (day_figures('2026-10-27')->>'invoices')::int=0);
\i fix_close_25_26.sql
select t.ok('تشغيل تاني ما بيكررش', (select count(*) from cash_closings where day>='2026-10-25')=2);
rollback;
