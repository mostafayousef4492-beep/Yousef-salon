\set ON_ERROR_STOP 1
\set QUIET 1
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000f7') on conflict do nothing;
insert into customers(user_id,name,phone) values ('00000000-0000-0000-0000-0000000000f7','عميل ميلاد','01090000077');
select t.as_('00000000-0000-0000-0000-0000000000f7');
select set_my_profile(null, date '1990-05-10', false);
select t.ok('العميل سجّل غلط', (my_profile()->>'birthday')='1990-05-10');
select set_my_profile(null, date '1991-06-11', false);
select t.ok('العميل عدّل بنفسه', (my_profile()->>'birthday')='1991-06-11');
select t.fl('العميل مش بيستخدم دالة الإدارة', $$select admin_set_customer_birthday((select id from customers where phone='01090000077'), date '1992-01-01')$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('الكاشير مرفوض', $$select admin_set_customer_birthday((select id from customers where phone='01090000077'), date '1992-01-01')$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select admin_set_customer_birthday((select id from customers where phone='01090000077'), date '1985-03-04');
select t.ok('المالك عدّل', (select birthday from customers where phone='01090000077')=date '1985-03-04');
select t.fl('تاريخ مستقبلي', $$select admin_set_customer_birthday((select id from customers where phone='01090000077'), current_date)$$);
select t.fl('عميل مش موجود', $$select admin_set_customer_birthday(-5, date '1985-03-04')$$);
select admin_set_customer_birthday((select id from customers where phone='01090000077'), null);
select t.ok('المالك مسح', (select birthday from customers where phone='01090000077') is null);
rollback;
select 'ALL BDAY EDIT TESTS PASSED';
