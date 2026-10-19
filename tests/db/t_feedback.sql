\set ON_ERROR_STOP 1
\set QUIET 1
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000f8') on conflict do nothing;
insert into customers(user_id,name,phone) values ('00000000-0000-0000-0000-0000000000f8','عميل رأي','01090000088');
select t.as_('00000000-0000-0000-0000-0000000000f8');
select send_feedback('الخدمة ممتازة', false);
select send_feedback('الانتظار طويل شوية', true);
select t.fl('رسالة قصيرة', $$select send_feedback('اا', false)$$);
select send_feedback('تالتة', false);
select t.fl('الحد اليومي', $$select send_feedback('رابعة', false)$$);
select t.ok('العميل ميقرأش الرسايل', (select count(*) from customer_feedback)=0);
reset role;
select t.ok('الباسم اتسجل باسمه', (select customer_id from customer_feedback where message='الخدمة ممتازة')=(select id from customers where phone='01090000088'));
select t.ok('المجهولة من غير هوية', (select customer_id is null from customer_feedback where message='الانتظار طويل شوية'));
select t.ok('المجهولة تاريخها باليوم بس', (select created_at=date_trunc('day',created_at) from customer_feedback where message='الانتظار طويل شوية'));
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك شايف الكل', (select count(*) from customer_feedback)=3);
update customer_feedback set read_at=now() where message='تالتة';
select t.ok('المالك علّم مقروءة', (select read_at is not null from customer_feedback where message='تالتة'));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.ok('الكاشير مش شايف', (select count(*) from customer_feedback)=0);
reset role;
-- وضع «باسمه دايمًا»: خيار «مجهول» بيتجاهل
insert into app_settings(key,value) values ('feedback_mode','"named"') on conflict (key) do update set value='"named"';
delete from feedback_quota;
select t.as_('00000000-0000-0000-0000-0000000000f8');
select send_feedback('رسالة وضع باسم', true);
reset role;
select t.ok('وضع named بيسجّل الاسم حتى لو طلب مجهول', (select customer_id is not null from customer_feedback where message='رسالة وضع باسم'));
insert into app_settings(key,value) values ('feedback_mode','"off"') on conflict (key) do update set value='"off"';
select t.as_('00000000-0000-0000-0000-0000000000f8');
select t.fl('وضع off', $$select send_feedback('مرفوضة', false)$$);
reset role;
rollback;
select 'ALL FEEDBACK TESTS PASSED';
