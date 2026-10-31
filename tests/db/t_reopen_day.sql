\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.anon_() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
begin;
delete from business_days; delete from cash_closings where day >= current_date - 10;
-- يوم اتفتح امبارح بعد الظهر (مش بتاريخ قديم) وفضل مفتوح لحد ما الساعة عدت 6 الصبح: لازم مفيش إزاحة
insert into business_days(day, opened_at, opened_by) values ((now() at time zone my_tz())::date - 1, ((now() at time zone my_tz())::date - 1 + time '14:00') at time zone my_tz(), :'own');
select t.ok('يوم مفتوح بعد 6 الصبح من غير فتح قديم: مفيش إزاحة', biz_shift_days() = 0 and (business_day_state()->>'backdated')::boolean = false);
-- يوم اتفتح بتاريخ قديم (منتصف الليل): الإزاحة شغالة
delete from business_days;
insert into business_days(day, opened_at, opened_by) values ((now() at time zone my_tz())::date - 3, ((now() at time zone my_tz())::date - 3)::timestamp at time zone my_tz(), :'own');
select t.ok('يوم قديم مفتوح بتاريخ مختار: الإزاحة شغالة', biz_shift_days() < 0);
select t.ok('state بيقول backdated', (business_day_state()->>'backdated')::boolean);

-- قفل يوم عادي وإعادة فتحه
delete from business_days;
insert into business_days(day, opened_at, opened_by) values ((now() at time zone my_tz())::date, now() - interval '3 hours', :'own');
insert into invoices(id,no,subtotal,total,payment_method,created_at) values (990101, 990101, 100, 100, 'cash', now() - interval '1 hour');
select t.as_(:'own');
select close_day((now() at time zone my_tz())::date, 100, 0, 0, 0, null) is not null as c \gset
reset role;
select t.ok('اتقفل', (select closed_at from business_days where day = (now() at time zone my_tz())::date) is not null and exists (select 1 from cash_closings where day = (now() at time zone my_tz())::date));
reset role;
select t.as_(:'cash');
select t.fl('الكاشير مايعيدش فتح', 'select reopen_business_day()');
reset role;
select t.anon_();
select t.fl('الزائر مايعيدش فتح', 'select reopen_business_day()');
reset role;
select t.as_(:'own');
select t.fl('يوم مش آخر يوم', 'select reopen_business_day(current_date - 40)');
select reopen_business_day() as st \gset
reset role;
select t.ok('رجع مفتوح', (:'st'::jsonb->>'open')::boolean);
select t.ok('الجرد اتشال وسجل في المحذوفات', not exists (select 1 from cash_closings where day = (now() at time zone my_tz())::date) and exists (select 1 from deletion_log where table_name = 'cash_closings'));
select t.ok('الفاتورة لسه موجودة', exists (select 1 from invoices where id = 990101));
select t.as_(:'own');
select t.fl('مينفعش يعيد فتح وفيه يوم مفتوح', 'select reopen_business_day()');
-- بيتقفل تاني بشكل سليم
select close_day((now() at time zone my_tz())::date, 100, 0, 0, 0, null) is not null as c2 \gset
reset role;
select t.ok('اتقفل تاني', exists (select 1 from cash_closings where day = (now() at time zone my_tz())::date));
select t.ok('وقت القفل بعد وقت الفتح', (select closed_at > opened_at from business_days where day = (now() at time zone my_tz())::date));

-- إصلاح البيانات: يوم قفله بوقت غلط
update business_days set closed_at = opened_at - interval '8 hours' where day = (now() at time zone my_tz())::date;
\i patch_reopen_day.sql
select t.ok('الإصلاح رجّع وقت القفل', (select closed_at > opened_at from business_days where day = (now() at time zone my_tz())::date));
rollback;
\echo ALL REOPEN TESTS DONE
