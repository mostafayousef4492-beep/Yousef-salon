\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_queue_by_time.sql
begin;
insert into customers(id,name,phone) values (101,'x1','01000000101'),(102,'x2','01000000102'),(103,'x3','01000000103'),(104,'x4','01000000104'),(105,'x5','01000000105') on conflict do nothing;
-- 3 مسا (حجزوا بدري) + 1 عصر (حجز متأخر) عند نفس الحلاق
insert into appointments(customer_id, barber_id, day, period, ticket_no, status, starts_at, sort_at) values
 (101, :'b1', current_date, 'evening',   1, 'upcoming', now(), now() - interval '5 hours'),
 (102, :'b1', current_date, 'evening',   2, 'upcoming', now(), now() - interval '4 hours'),
 (103, :'b1', current_date, 'evening',   3, 'upcoming', now(), now() - interval '3 hours');
insert into appointments(customer_id, barber_id, day, period, ticket_no, status, starts_at, sort_at) values
 (1, :'b1', current_date, 'afternoon', 1, 'upcoming', now(), now() - interval '1 minute') returning id as late_id \gset
insert into appointments(customer_id, barber_id, day, period, ticket_no, status, starts_at, sort_at) values
 (104, :'b1', current_date, 'evening',   4, 'upcoming', now(), now() + interval '1 minute') returning id as after_id \gset
select t.ok('قدام الحجز المتأخر 3 (مش 0 بتاعة العصر بس)', p11_ahead(:late_id) = 3);
select t.ok('الحجز اللي بعده قدامه 4', p11_ahead(:after_id) = 4);
select t.ok('queue_core بتقول نفس الرقم', (p11_queue_core(:late_id)->>'ahead')::int = 3);
select t.ok('وقت الانتظار المتوقع > 0', (p11_queue_core(:late_id)->>'est_wait_min')::int > 0);
select t.ok('public_ticket بترجّع 3', (select ahead from public_ticket(:late_id, '01000000001')) = 3);
-- التخطّي بيشتغل عبر الفترات: التذكرة 3 مسا تعدّي اللي بعدها (العصر)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
select skip_move((select id from appointments where barber_id=:'b1' and ticket_no=3 and period='evening' and day=current_date), 'one');
select t.ok('بعد التخطّي: العصر بقى قدامه 2', p11_ahead(:late_id) = 2);
rollback;
\echo QBT DONE
