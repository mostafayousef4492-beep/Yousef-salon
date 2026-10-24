\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.back() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fails(n text, q text, part text default null) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if part is not null and position(part in sqlerrm) = 0 then raise exception 'FAIL: % (رسالة مختلفة: %)', n, sqlerrm; end if;
    raise notice 'PASS: % [%]', n, sqlerrm; return;
  end;
  raise exception 'FAIL: % (المفروض يفشل)', n;
end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
begin;
delete from business_days; delete from cash_closings where day >= current_date - 5;
-- 1) مفيش يوم مفتوح: نفس التاريخ العادي
select t.ok('مفيش يوم مفتوح = تاريخ النهارده', biz_today() = (now() at time zone my_tz())::date and (business_day_state()->>'open')::boolean = false);
-- 2) الكاشير مايفتحش، المالك يفتح
select t.as_(:'cash');
select t.fails('الكاشير مايفتحش اليوم', 'select open_business_day()', 'غير مصرح');
select t.back();
select t.as_(:'own');
select open_business_day() as st \gset
select t.back();
select t.ok('المالك فتح اليوم', (:'st'::jsonb->>'open')::boolean and (:'st'::jsonb->>'day')::date = (now() at time zone my_tz())::date);
select t.as_(:'own');
select t.fails('مينفعش يفتح يومين', 'select open_business_day()', 'فيه يوم مفتوح بالفعل');
select t.back();
-- 3) يوم عمل بدأ إمبارح وفاضل شغّال بعد 12
delete from business_days;
insert into business_days(day, opened_at, opened_by) values ((now() at time zone my_tz())::date - 1, now() - interval '30 hours', :'own');
select t.ok('بعد 12: النهارده لسه يوم إمبارح', biz_today() = (now() at time zone my_tz())::date - 1);
select t.ok('p16_today بيتبع يوم العمل', p16_today() = (now() at time zone my_tz())::date - 1);
-- 4) فاتورتين: واحدة جوه فترة اليوم المفتوح وواحدة قبله
insert into invoices(id,no,subtotal,total,payment_method,created_at) values
 (990001, 990001, 100, 100, 'cash', now() - interval '2 hours'),
 (990002, 990002, 50, 50, 'cash', now() - interval '40 hours');
select t.ok('الدرج: فاتورة بعد 12 جوه يوم العمل بتتحسب', (day_figures((now() at time zone my_tz())::date - 1)->>'cash_sales')::numeric = 100);
select t.ok('التاريخ العادي الجديد مابيحسبش اللي جوه يوم العمل', (day_figures((now() at time zone my_tz())::date)->>'cash_sales')::numeric = 0);
-- 5) قفل اليوم = جرد الدرج
select t.as_(:'own');
select t.fails('الجرد بيطلب الأرقام', 'select close_day((now() at time zone my_tz())::date - 1, null, 0, 0, null, null)', 'اكتب الكاش');
select close_day((now() at time zone my_tz())::date - 1, 100, 0, 0, 0, 'تجربة') as cl \gset
select t.back();
select t.ok('الجرد اتسجل', exists (select 1 from cash_closings where day = (now() at time zone my_tz())::date - 1));
select t.ok('اليوم اتقفل مع الجرد', (select closed_at is not null from business_days where day = (now() at time zone my_tz())::date - 1));
select t.ok('بعد القفل: رجع التاريخ العادي', biz_today() = (now() at time zone my_tz())::date and (business_day_state()->>'open')::boolean = false);
-- 6) فتح يوم جديد
select t.as_(:'own');
select open_business_day() as st2 \gset
select t.back();
select t.ok('فتح اليوم الجديد بتاريخ النهارده', (:'st2'::jsonb->>'day')::date = (now() at time zone my_tz())::date);
select t.ok('بداية فترته بعد قفل اللي قبله', (:'st2'::jsonb->>'window_from')::timestamptz >= (select closed_at from business_days where day = (now() at time zone my_tz())::date - 1) - interval '1 second');
-- 7) قفل يوم النهارده ثم محاولة فتحه تاني (الجرد موجود)
select t.as_(:'own');
select close_day((now() at time zone my_tz())::date, 0, 0, 0, 0, null) as cl2 \gset
select t.fails('مينفعش يفتح يوم اتجرد', 'select open_business_day()', 'اتقفل قبل كده');
select t.back();
delete from cash_closings where day = (now() at time zone my_tz())::date;
select t.as_(:'own');
select open_business_day() as st3 \gset
select t.back();
select t.ok('بعد مسح الجرد يتفتح تاني', (:'st3'::jsonb->>'open')::boolean);
-- 8) الحجز على يوم العمل
delete from business_days; insert into business_days(day, opened_at) values ((now() at time zone my_tz())::date - 1, now() - interval '30 hours');
select t.ok('available_barbers شغّالة على يوم العمل', (select count(*) >= 0 from available_barbers(biz_today(), 'evening')));
select t.ok('مفيش حركة اتمسحت (الفواتير)', (select count(*) from invoices where id in (990001, 990002)) = 2);
rollback;
select 'BUSINESS DAY DONE';
