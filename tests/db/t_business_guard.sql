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
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
begin;
delete from business_days; delete from cash_closings where day >= current_date - 5;
insert into invoices(id,no,subtotal,total,payment_method,created_at) values
 (990011, 990011, 100, 100, 'cash', ((now() at time zone my_tz())::date - 1)::timestamp at time zone my_tz() + interval '12 hours');
-- 1) إمبارح فيه شغل ومتقفلش: المالك مايقدرش يفتح اليوم الجديد
select t.as_(:'own');
select t.fails('مينفعش يفتح يوم وإمبارح لسه ما اتقفلش', 'select open_business_day()', 'ما اتقفلش بجرد');
select close_day((now() at time zone my_tz())::date - 1, 100, 0, 0, 0, 'تجربة') as cl \gset
select open_business_day() as st \gset
select t.back();
select t.ok('بعد جرد إمبارح يتفتح عادي', (:'st'::jsonb->>'open')::boolean);
-- 2) إمبارح من غير شغل: يتفتح عادي
delete from business_days; delete from cash_closings where day >= current_date - 5; delete from invoices where id = 990011;
select t.as_(:'own');
select open_business_day() as st2 \gset
select t.back();
select t.ok('إمبارح من غير شغل: يتفتح', (:'st2'::jsonb->>'open')::boolean);
-- 3) سكربت العلاج: يوم النهارده اتفتح بالغلط → يرجع يوم إمبارح
delete from business_days;
insert into business_days(day, opened_at, opened_by) values ((now() at time zone my_tz())::date, now() - interval '1 hour', :'own');
\set fixsql `sed -e "s/2026-10-25/$(date +%F)/" -e "s/2026-10-24/$(date -d yesterday +%F)/" /home/claude/yousef-salon/fix_open_day_24.sql`
:fixsql
select t.ok('العلاج: إمبارح هو المفتوح', (select count(*) = 1 and min(day) = (now() at time zone my_tz())::date - 1 from business_days where closed_at is null));
select t.ok('العلاج: بداية إمبارح من أول اليوم', (select opened_at = (day::timestamp at time zone my_tz()) from business_days where closed_at is null));
select t.ok('العلاج: biz_today رجع لإمبارح', biz_today() = (now() at time zone my_tz())::date - 1);
-- 4) قائمة أيام العمل للتقارير
select t.as_(:'own');
select business_days_list() as bl \gset
select t.back();
select t.ok('القائمة فيها اليوم المفتوح', jsonb_array_length(:'bl'::jsonb) = 1);
select t.as_('00000000-0000-0000-0000-0000000000c1');
select t.ok('العميل مايشوفش القائمة', business_days_list() = '[]'::jsonb);
select t.back();
rollback;
select 'BUSINESS GUARD DONE';
