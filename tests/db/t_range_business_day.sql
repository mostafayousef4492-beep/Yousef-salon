\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
begin;
delete from business_days; delete from cash_closings; delete from invoices where id >= 990200;
-- يوم عمل: امبارح 20:00 → النهارده 03:00 (بعد منتصف الليل)، مقفول
insert into business_days(day, opened_at, closed_at) values ((now() at time zone my_tz())::date - 1, ((now() at time zone my_tz())::date - 1 + time '12:00') at time zone my_tz(), ((now() at time zone my_tz())::date + time '04:00') at time zone my_tz());
insert into invoices(id,no,subtotal,total,payment_method,created_at) values
 (990201, 990201, 100, 100, 'cash', ((now() at time zone my_tz())::date - 1 + time '20:00') at time zone my_tz()),
 (990202, 990202, 50, 50, 'cash', ((now() at time zone my_tz())::date + time '01:30') at time zone my_tz());
select t.ok('يوم العمل بيشمل فاتورة بعد منتصف الليل', (day_figures((now() at time zone my_tz())::date - 1)->>'cash_sales')::numeric = 150);
select t.ok('التقرير الشامل بنفس الرقم لليوم', (range_figures((now() at time zone my_tz())::date - 1, (now() at time zone my_tz())::date - 1)->>'cash_sales')::numeric = 150);
select t.ok('اليوم التاني مفيهوش الفاتورة بتاعة بعد منتصف الليل', (range_figures((now() at time zone my_tz())::date, (now() at time zone my_tz())::date)->>'cash_sales')::numeric = 0);
select t.ok('الفترة الكاملة نفس المجموع', (range_figures((now() at time zone my_tz())::date - 1, (now() at time zone my_tz())::date)->>'cash_sales')::numeric = 150);
rollback;
\echo RANGE BUSINESS DAY DONE
