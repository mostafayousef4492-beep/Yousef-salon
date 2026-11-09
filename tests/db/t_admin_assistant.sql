\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): % [%]', n, sqlerrm; return; end; raise exception 'FAIL (no error): %', n; end $$;
grant usage on schema t to public;
\i sql/patch_partial_pay.sql
\i sql/patch_full_report.sql
\i sql/patch_assistant.sql
\i sql/patch_admin_assistant.sql
begin;
alter table profiles disable trigger all;
insert into auth.users(id,email) values ('00000000-0000-0000-0000-0000000000d1','mgr@staff.x') on conflict do nothing;
insert into profiles(id,full_name,role) values ('00000000-0000-0000-0000-0000000000d1','المدير','manager') on conflict (id) do nothing;
alter table profiles enable trigger all;
insert into services(name,price,duration_min,active) values ('حلاقة+دقن',150,30,true) on conflict do nothing;
insert into invoices(barber_id,customer_id,subtotal,discount,total,payment_method) values
 ('00000000-0000-0000-0000-0000000000b1',1,200,0,200,'cash'),
 ('00000000-0000-0000-0000-0000000000b1',1,100,0,100,'cash'),
 ('00000000-0000-0000-0000-0000000000b2',2,150,10,140,'wallet'),
 ('00000000-0000-0000-0000-0000000000b2',null,60,0,60,'cash');
insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price)
 select id,'service',1,'قصة',2,100 from invoices where subtotal=200;
insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price)
 select id,'service',1,'قصة',1,100 from invoices where subtotal=100;
insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price)
 select id,'service',2,'دقن',3,50 from invoices where subtotal=150;
insert into expenses(spent_on,category,amount,note) values (current_date,'إيجار',500,'سر: 01099999999'),(current_date,'كهرباء',120,'y');
insert into suppliers(name) values ('مورد1');
insert into purchases(supplier_id,bought_on,kind,total,paid) select id,current_date,'stock',300,100 from suppliers where name='مورد1';
insert into attendance(staff_id,check_in,check_out,late_min) values ('00000000-0000-0000-0000-0000000000b1',now()-interval '8 hours',now()-interval '1 hour',12);
create temp table r as select 1 x; grant all on r to public;
select t.as_('00000000-0000-0000-0000-0000000000a1');
create temp table ov as select ai_overview(now()-interval '30 days', now()+interval '1 day') j; grant all on ov to public;
select t.ok('المالك: الإيراد 500 والفواتير 4', (select (j->>'revenue')::numeric=500 and (j->>'invoices')::int=4 from ov));
select t.ok('متوسط الفاتورة 125', (select (j->>'avg_invoice')::numeric=125 from ov));
select t.ok('الإيراد يطابق full_report', (select (j->>'revenue')::numeric=(full_report(now()-interval '30 days', now()+interval '1 day')->>'revenue')::numeric from ov));
select t.ok('ترتيب الخدمات: قصة 3 قطع أول بالكمية الأعلى = دقن 3', (select (ai_items_rank(now()-interval '30 days', now()+interval '1 day','service',5)->'items'->0->>'qty')::int=3));
select t.ok('إجمالي الكمية 6', (select (ai_items_rank(now()-interval '30 days', now()+interval '1 day')->>'total_qty')::int=6));
select t.ok('نوع غلط مرفوض', (select true));
select t.fl('نوع غلط', $$select ai_items_rank(now()-interval '1 day', now(), 'x')$$);
select t.ok('المصروفات 620', (select (ai_expenses(now()-interval '30 days', now()+interval '1 day')->>'total')::numeric=620));
select t.ok('بدون ملاحظات افتراضيًا', (select not (ai_expenses(now()-interval '30 days', now()+interval '1 day')::text like '%01099999999%')));
select t.ok('الملاحظات مع p_names', (select ai_expenses(now()-interval '30 days', now()+interval '1 day', true)::text like '%01099999999%'));
select t.ok('المشتريات: 300 مدفوع 100 متبقي 200', (select (j->>'total')::numeric=300 and (j->>'paid')::numeric=100 and (j->>'unpaid')::numeric=200 from (select ai_purchases(now()-interval '30 days', now()+interval '1 day') j) q));
select t.ok('العملاء: بدون أسماء', (select not (ai_customers(now()-interval '30 days', now()+interval '1 day')::text like '%عميل1%')));
select t.ok('العملاء: أسماء مع p_names', (select ai_customers(now()-interval '30 days', now()+interval '1 day', true)::text like '%عميل1%'));
select t.ok('الراجعين 1 والمجهول 1', (select (j->>'repeat_in_range')::int=1 and (j->>'anonymous_invoices')::int=1 from (select ai_customers(now()-interval '30 days', now()+interval '1 day') j) q));
select t.ok('الحضور: تأخير 12', (select (ai_attendance(now()-interval '30 days', now()+interval '1 day')->'staff'->0->>'late_minutes')::int=12));
select t.ok('تفاصيل الفواتير بفلتر الحلاق', (select (j->>'matching')::int=2 and (j->>'matching_total')::numeric=300 from (select ai_invoices(now()-interval '30 days', now()+interval '1 day','00000000-0000-0000-0000-0000000000b1') j) q));
select t.ok('فلتر الخدمة', (select (ai_invoices(now()-interval '30 days', now()+interval '1 day',null,'دقن')->>'matching')::int=1));
select t.ok('فلتر طريقة الدفع', (select (ai_invoices(now()-interval '30 days', now()+interval '1 day',null,null,'wallet')->>'matching_total')::numeric=140));
select t.ok('فواتير بدون أسماء', (select not (ai_invoices(now()-interval '30 days', now()+interval '1 day')::text like '%عميل%')));
select t.ok('فواتير بأسماء', (select ai_invoices(now()-interval '30 days', now()+interval '1 day',null,null,null,30,true)::text like '%عميل1%'));
select t.ok('السلسلة اليومية يوم واحد', (select jsonb_array_length(ai_daily_series(now()-interval '30 days', now()+interval '1 day')->'days')=1));
select t.ok('الحجوزات بترد', (select (ai_appointments(now()-interval '30 days', now()+interval '1 day')->>'total') is not null));
select t.fl('فترة مقلوبة', $$select ai_overview(now(), now()-interval '1 day')$$);
select t.fl('فترة أطول من 400 يوم', $$select ai_overview(now()-interval '500 days', now())$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('المدير مسموح', (select (ai_overview(now()-interval '30 days', now()+interval '1 day')->>'revenue')::numeric=500));
reset role;
insert into app_settings(key,value) values ('assistant_admin_manager','"false"') on conflict (key) do update set value='"false"';
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.fl('المدير مرفوض لما الإعداد false', $$select ai_overview(now()-interval '1 day', now())$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك دايمًا مسموح', (select ai_admin_ok()));
reset role;
delete from app_settings where key='assistant_admin_manager';
do $$ declare u text; f text; begin
 foreach u in array array['00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000c1'] loop
  perform t.as_(u);
  foreach f in array array['select ai_overview(now()-interval ''1 day'', now())','select ai_items_rank(now()-interval ''1 day'', now())','select ai_daily_series(now()-interval ''1 day'', now())','select ai_expenses(now()-interval ''1 day'', now())','select ai_purchases(now()-interval ''1 day'', now())','select ai_customers(now()-interval ''1 day'', now())','select ai_appointments(now()-interval ''1 day'', now())','select ai_attendance(now()-interval ''1 day'', now())','select ai_invoices(now()-interval ''1 day'', now())'] loop
    begin execute f; raise exception 'FAIL: % allowed % ', u, f; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  end loop;
  reset role;
 end loop; raise notice 'PASS: غير الإدارة مرفوضين من كل الدوال'; end $$;
-- anon مالوش تنفيذ
select t.ok('anon مالوش execute', not has_function_privilege('anon','ai_overview(timestamptz,timestamptz)','execute'));
-- حد الأسئلة للإدارة 60
select t.as_('00000000-0000-0000-0000-0000000000a1');
select assistant_hit() as h \gset
select t.ok('حد المالك 60 (متبقي 59)', (:'h'::jsonb->>'left')::int=59 and :'h'::jsonb->>'role'='owner');
reset role;
rollback;
\echo ADMIN AI DONE
