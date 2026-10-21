\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl3(n text, q text, part text default null) returns void language plpgsql as $$ begin begin execute q; exception when others then if part is not null and position(part in sqlerrm)=0 then raise exception 'FAIL: % (رسالة مختلفة: %)', n, sqlerrm; end if; raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
begin;
\set own '00000000-0000-0000-0000-0000000000a1'
\set mgr '00000000-0000-0000-0000-0000000000c3'
\set b1 '00000000-0000-0000-0000-0000000000b1'
insert into profiles(id,full_name,role,salary,created_at) values (:'mgr','مدير','manager',0,now()-interval '10 days') on conflict (id) do update set role='manager';
delete from audit_log where false;
-- إضافة وتعديل بيتسجلوا
select t.as_(:'own');
insert into staff_transactions(staff_id,kind,amount,note) values (:'b1','advance',100,'سلفة تجربة') returning id as tx1 \gset
reset role;
update staff_transactions set amount=150 where id=:tx1;
update staff_transactions set amount=150 where id=:tx1;
select t.ok('الإضافة اتسجلت باسم المالك', (select count(*) from audit_log where table_name='staff_transactions' and row_id=:'tx1' and op='insert' and actor_role='owner')=1);
select t.ok('التعديل اتسجل (قبل/بعد) والتعديل الفاضي لأ', (select count(*) from audit_log where table_name='staff_transactions' and row_id=:'tx1' and op='update')=1
  and (select (old_data->>'amount')::numeric=100 and (new_data->>'amount')::numeric=150 and changed=array['amount'] from audit_log where table_name='staff_transactions' and row_id=:'tx1' and op='update'));
-- المدير يحذف حركة موظف
select t.as_(:'mgr');
select admin_delete_record('staff_transactions', :'tx1'::text);
reset role;
select t.ok('حذف المدير اتسجل بكل البيانات واسمه', (select count(*)=1 and bool_and(actor_role='manager') and bool_and((old_data->>'note')='سلفة تجربة') from audit_log where table_name='staff_transactions' and row_id=:'tx1' and op='delete'));
-- المدير يحذف حضور
select t.as_(:'own'); insert into attendance(staff_id,late_min) values (:'b1',0) returning id::text as att1 \gset
reset role;
select t.as_(:'mgr'); select admin_att_delete(:'att1'); reset role;
select t.ok('حذف الحضور بالمدير اشتغل واتسجل', (select count(*) from audit_log where table_name='attendance' and row_id=:'att1' and op='delete' and actor_role='manager')=1);
-- المدير يحذف حجز
insert into customers(name,phone) values ('ع','01066666666') on conflict do nothing;
insert into appointments(customer_id,barber_id,starts_at,status,day,period) select c.id,:'b1',now(),'upcoming',current_date,'evening' from customers c where phone='01066666666' limit 1 returning id::text as ap1 \gset
select t.as_(:'mgr'); select admin_delete_appointment(:'ap1'); reset role;
select t.ok('حذف الحجز بالمدير اشتغل واتسجل', (select count(*) from audit_log where table_name='appointments' and row_id=:'ap1' and op='delete' and actor_role='manager')=1);
-- المدير مش بيحذف الفلوس
insert into cash_moves(kind,amount,note) values ('deposit',10,'x') returning id::text as cm1 \gset
select t.as_(:'mgr');
select t.fl3('المدير مايحذفش حركة درج', format($$select admin_delete_record('cash_moves', %L)$$, :'cm1'), 'غير مصرح');
reset role;
-- الأرشيف: المالك يقرا، المدير لأ، ومفيش تعديل ولا مسح
select t.as_(:'mgr'); select t.ok('المدير مبيشوفش الأرشيف', (select count(*) from audit_log)=0); reset role;
select t.as_(:'own'); select t.ok('المالك بيشوف', (select count(*) from audit_log)>=6); reset role;
select t.fl3('الأرشيف مبيتعدلش (حتى من السوبر)', $$update audit_log set summary='x'$$, 'للقراءة فقط');
select t.fl3('الأرشيف مبيتمسحش', $$delete from audit_log$$, 'للقراءة فقط');
select t.as_(:'own');
select t.fl3('المالك نفسه مايقدرش يمسحه', $$delete from audit_log$$);
reset role;
rollback;
\echo AUDIT DONE
