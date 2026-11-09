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
\i sql/patch_manager_assistant.sql
begin;
alter table profiles disable trigger all;
insert into auth.users(id,email) values ('00000000-0000-0000-0000-0000000000d1','mgr@staff.x') on conflict do nothing;
insert into profiles(id,full_name,role,code) values ('00000000-0000-0000-0000-0000000000d1','المدير','manager','900') on conflict (id) do nothing;
update profiles set commission_pct=40, salary=3000, code='101' where id='00000000-0000-0000-0000-0000000000b1';
alter table profiles enable trigger all;
insert into invoices(barber_id,customer_id,subtotal,discount,total,payment_method,unpaid) values
 ('00000000-0000-0000-0000-0000000000b1',1,200,0,200,'cash',0),
 ('00000000-0000-0000-0000-0000000000b1',1,100,0,70,'cash',30);
insert into invoice_items(invoice_id,item_type,item_id,name,qty,unit_price) select id,'service',1,'قصة',1,100 from invoices where subtotal=100;
insert into staff_transactions(staff_id,kind,amount,note) values ('00000000-0000-0000-0000-0000000000b1','advance',50,'سلفة'),('00000000-0000-0000-0000-0000000000b1','deduction',10,'خصم'),('00000000-0000-0000-0000-0000000000b1','bonus',30,'مكافأة');
insert into salary_payments(staff_id,period,amount,paid_on,paid_from) values ('00000000-0000-0000-0000-0000000000b1',date_trunc('month',now())::date,500,current_date,'drawer');
insert into attendance(staff_id,check_in,check_out,late_min) values ('00000000-0000-0000-0000-0000000000b1',now()-interval '8 hours',now()-interval '1 hour',12);
-- الأدوار
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك: mode=owner وتحليل مسموح', (select ai_mode()='owner' and ai_admin_ok() and ai_mgr_ok()));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('المدير: mode=manager، التحليل ممنوع، المساعد التشغيلي مسموح', (select ai_mode()='manager' and not ai_admin_ok() and ai_mgr_ok()));
select t.fl('المدير ممنوع من التحليل', $$select ai_overview(now()-interval '1 day', now())$$);
select t.ok('المدير: بحث موظف بالاسم', (select jsonb_array_length(ai_find_staff('أحمد')->'staff')=1));
select t.ok('المدير: بحث موظف بالكود', (select ai_find_staff('101')->'staff'->0->>'name'='أحمد'));
create temp table m as select ai_staff_money('00000000-0000-0000-0000-0000000000b1', now()-interval '30 days', now()+interval '1 day') j; grant all on m to public;
select t.ok('أرقام الموظف: مبيعات 270 وسلف 50 وخصم 10', (select (j->'summary'->>'sales')::numeric=270 and (j->'summary'->>'advances')::numeric=50 and (j->'summary'->>'deductions')::numeric=10 from m));
select t.ok('حركات الموظف 3 والمصروف من الراتب 500', (select jsonb_array_length(j->'transactions')=3 and (j->>'salary_paid_in_range')::numeric=500 from m));
select t.ok('الاسم والنسبة والمرتب', (select j->>'name'='أحمد' and (j->>'commission_pct')::numeric=40 and (j->>'monthly_salary')::numeric=3000 from m));
select t.ok('حضور الموظف: تأخير 12', (select (ai_staff_attendance('00000000-0000-0000-0000-0000000000b1', now()-interval '30 days', now()+interval '1 day')->>'total_late_minutes')::int=12));
select t.fl('عميل مش موجود', $$select ai_customer_info(99999)$$);
select t.fl('موظف مش موجود', $$select ai_staff_money('00000000-0000-0000-0000-00000000ffff', now()-interval '1 day', now())$$);
select t.fl('عميل id بدل موظف', $$select ai_staff_money('00000000-0000-0000-0000-0000000000c1', now()-interval '1 day', now())$$);
select t.fl('بحث عميل قصير', $$select ai_customer_find('ع')$$);
select t.ok('بحث عميل بالاسم', (select jsonb_array_length(ai_customer_find('عميل1')->'customers')=1));
select t.ok('بحث عميل بالموبايل', (select ai_customer_find('01000000001')->'customers'->0->>'name'='عميل1'));
select t.ok('بحث العميل مابيرجّعش الموبايل', (select not (ai_customer_find('01000000001')::text like '%01000000001%')));
create temp table ci as select ai_customer_info(1) j; grant all on ci to public;
select t.ok('ملف العميل: إنفاق 270 وفاتورتين ودين 30', (select (j->>'total_spent')::numeric=270 and (j->>'invoices_count')::int=2 and (j->>'debt_remaining')::numeric=30 from ci));
select t.ok('ملف العميل بدون موبايل', (select not (j::text like '%01000000001%') and (j->>'has_phone')::boolean from ci));
select t.ok('ملف العميل: آخر فواتير بالأصناف', (select (j->'recent_invoices')::text like '%قصة ×1%' from ci));
reset role;
-- مدير مقفول بالإعداد
insert into app_settings(key,value) values ('assistant_manager_enabled','"false"') on conflict (key) do update set value='"false"';
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('المدير مقفول: mode=null', (select ai_mode() is null and not ai_mgr_ok()));
select t.fl('المدير المقفول مرفوض', $$select ai_find_staff('أحمد')$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك مش بيتأثر بقفل المدير', (select ai_mode()='owner'));
select t.ok('المالك يقدر يستخدم أدوات المدير', (select jsonb_array_length(ai_find_staff('أحمد')->'staff')=1));
reset role;
delete from app_settings where key='assistant_manager_enabled';
-- باقي الأدوار مرفوضة
do $$ declare u text; f text; begin
 foreach u in array array['00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000c1'] loop
  perform t.as_(u);
  foreach f in array array['select ai_find_staff(''أحمد'')','select ai_staff_money(''00000000-0000-0000-0000-0000000000b1'', now()-interval ''1 day'', now())','select ai_staff_attendance(''00000000-0000-0000-0000-0000000000b1'', now()-interval ''1 day'', now())','select ai_customer_find(''عميل'')','select ai_customer_info(1)'] loop
    begin execute f; raise exception 'FAIL: % allowed % ', u, f; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
  end loop;
  if (select ai_mode()) is not null then raise exception 'FAIL: mode for %', u; end if;
  reset role;
 end loop; raise notice 'PASS: كاشير/حلاق/عميل مرفوضين ومالهمش mode'; end $$;
select t.ok('anon مالوش execute', not has_function_privilege('anon','ai_customer_info(bigint)','execute') and not has_function_privilege('anon','ai_mode()','execute'));
select t.as_('00000000-0000-0000-0000-0000000000d1');
select assistant_hit() as h \gset
select t.ok('حد المدير 60', (:'h'::jsonb->>'left')::int=59 and :'h'::jsonb->>'role'='manager');
reset role;
rollback;
\echo MGR AI DONE
