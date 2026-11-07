\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
grant usage on schema t to public;
\set b1 '00000000-0000-0000-0000-0000000000b1'
\i sql/patch_carry_over.sql
begin;
insert into customers(id,name,phone) values (101,'x1','01000000101'),(102,'x2','01000000102'),(103,'x3','01000000103'),(104,'x4','01000000104') on conflict do nothing;
-- أمس: 2 قادمة + 1 وصل + 1 في الخدمة ، واليوم: حجز عادي
insert into appointments(customer_id, barber_id, day, period, ticket_no, queue_no, status, starts_at, sort_at) values
 (101, :'b1', current_date-1, 'evening', 1, 91, 'upcoming',   now(), now() - interval '30 hours'),
 (102, :'b1', current_date-1, 'evening', 2, 92, 'checked_in', now(), now() - interval '29 hours'),
 (103, :'b1', current_date-1, 'evening', 3, 93, 'upcoming',   now(), now() - interval '28 hours');
insert into appointments(customer_id, barber_id, day, period, ticket_no, queue_no, status, starts_at, sort_at) values
 (104, :'b1', current_date, 'morning', 1, 1, 'upcoming', now(), now() - interval '1 hour');
select p31_carry_over(current_date) as n \gset
select t.ok('اترحّل 3', :n = 3);
select t.ok('كلهم اتنقلوا لليوم وحالتهم قادمة', (select count(*) from appointments where customer_id in (101,102,103) and day=current_date and status::text='upcoming') = 3);
select t.ok('carried_from = أمس', (select count(*) from appointments where customer_id in (101,102,103) and carried_from = current_date-1) = 3);
select t.ok('الترتيب: 101 ثم 102 ثم 103 قبل 104', (select array_agg(customer_id order by sort_at, id) from appointments where barber_id=:'b1' and day=current_date) = array[101,102,103,104]::bigint[]);
select t.ok('أول حجز المرحّل قدامه 0', p11_ahead((select id from appointments where customer_id=101)) = 0);
select t.ok('104 قدامه 3', p11_ahead((select id from appointments where customer_id=104)) = 3);
select t.ok('إشعار للزبون', (select count(*) from customer_notifications where kind='carried_over' and customer_id in (101,102,103)) = 3);
select t.ok('تشغيل تاني مفيش جديد', p31_carry_over(current_date) = 0);
-- تذكرة في الخدمة ما بتتنقلش
insert into appointments(customer_id, barber_id, day, period, ticket_no, queue_no, status, starts_at) values (1, :'b1', current_date-1, 'evening', 9, 99, 'checked_in', now()) returning id as sid \gset
update appointments set status='in_service' where id=:sid;
select t.ok('in_service ما اترحلتش', p31_carry_over(current_date) = 0 and (select day from appointments where id=:sid) = current_date-1);
-- حضور الحلاق
insert into attendance(staff_id, check_in) values (:'b1', now());
select t.ok('إشعار الحلاق وصل', (select count(*) from customer_notifications where kind='carried_barber_in') = 3);
rollback;
\echo CO DONE
