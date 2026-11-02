\set ON_ERROR_STOP 1
\set QUIET 1
-- اختبار patch_cafe_shift_staffdrinks.sql (بعد t_cafe_staff). مشروب استاف + وردية الموظف.
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL (no error): %', n; end $$;
grant usage on schema t to public;
\set mgr '00000000-0000-0000-0000-0000000000a3'
\set cf '00000000-0000-0000-0000-0000000000c1'
\set cf2 '00000000-0000-0000-0000-0000000000c2'
\set bar '00000000-0000-0000-0000-0000000000b1'
begin;
insert into auth.users(id,email) values (:'mgr','mgr@t.t'),(:'cf','cf@t.t'),(:'cf2','cf2@t.t') on conflict do nothing;
insert into profiles(id, full_name, role) values (:'mgr','مدير','manager'),(:'cf','موظف كوفي','assistant'),(:'cf2','موظف كوفي 2','assistant') on conflict do nothing;
update profiles set perms = '{"use_cafe": true}'::jsonb where id in (:'cf', :'cf2');
delete from business_days; delete from cash_closings where day >= current_date - 5; delete from attendance where staff_id in (:'cf', :'cf2');
insert into business_days(day, opened_at) values (biz_today(), now() - interval '10 hours');
update cafe_products set cost = 4, price = 10, track_stock = true, stock = 50 where name = 'شاي';
select id as tea from cafe_products where name = 'شاي' \gset
\i patch_cafe_shift_staffdrinks.sql
\i patch_cafe_shift_staffdrinks.sql
-- ===== الوردية =====
insert into attendance(staff_id, check_in, check_out) values (:'cf', now() - interval '4 hours', now() - interval '2 hours');
insert into attendance(staff_id, check_in) values (:'cf2', now() - interval '1 hour');
select t.as_(:'cf');
select cafe_sell(format('[{"id":%s,"qty":1}]', :tea)::jsonb, 'cash') as s1 \gset
select cafe_sell(format('[{"id":%s,"qty":2}]', :tea)::jsonb, 'cash') as s2 \gset
reset role;
select t.as_(:'cf2');
select cafe_sell(format('[{"id":%s,"qty":3}]', :tea)::jsonb, 'cash') as s3 \gset
reset role;
-- s1 جوه وردية cf (قبل 3 ساعات)، s2 بعد انصرافه (قبل 30 دقيقة)، s3 بتاعة cf2 جوه ورديته
update cafe_sales set created_at = now() - interval '3 hours' where id = :s1;
update cafe_sales set created_at = now() - interval '30 minutes' where id = :s2;
update cafe_sales set created_at = now() - interval '30 minutes' where id = :s3;
select t.as_(:'cf');
select t.ok('موظف 1 يشوف مبيعات ورديته بس (طلب واحد = 10)', (cafe_staff_day()->'sales'->>'orders')::int = 1 and (cafe_staff_day()->'sales'->>'cash')::numeric = 10);
select t.ok('الوردية متقفلة وفيها وقت', (cafe_staff_day()->'shift'->>'open')::boolean = false and cafe_staff_day()->'shift'->>'from' is not null);
select t.ok('آخر العمليات: طلب واحد بس', jsonb_array_length(cafe_recent_sales(30)) = 1);
reset role;
select t.as_(:'cf2');
select t.ok('موظف 2 يشوف بتاعه بس (30)', (cafe_staff_day()->'sales'->>'orders')::int = 1 and (cafe_staff_day()->'sales'->>'cash')::numeric = 30 and (cafe_staff_day()->'shift'->>'open')::boolean);
select t.ok('موظف 2 مايشوفش عمليات موظف 1', jsonb_array_length(cafe_recent_sales(30)) = 1);
reset role;
select t.as_(:'mgr');
select t.ok('المدير يشوف كله (3 طلبات = 60)', (cafe_staff_day()->'sales'->>'orders')::int = 3 and (cafe_staff_day()->'sales'->>'cash')::numeric = 60 and cafe_staff_day()->'shift' = 'null'::jsonb);
select t.ok('المدير آخر العمليات 3', jsonb_array_length(cafe_recent_sales(30)) = 3);
reset role;
-- مفيش حضور = مفيش حاجة
delete from attendance where staff_id = :'cf';
select t.as_(:'cf');
select t.ok('من غير حضور: مفيش مبيعات ولا عمليات', (cafe_staff_day()->'sales'->>'orders')::int = 0 and jsonb_array_length(cafe_recent_sales(30)) = 0 and cafe_staff_day()->'shift'->>'from' is null);
reset role;
-- ===== مشروب استاف =====
select (day_figures(biz_today())->>'cash_sales')::numeric as cash_before \gset
select t.as_(:'cf2');
select cafe_sell(format('[{"id":%s,"qty":2}]', :tea)::jsonb, 'staff', null, 'أحمد الحلاق') as st \gset
select t.fl('مشروب استاف على فاتورة ممنوع', format('select cafe_sell(''[{"id":%s,"qty":1}]'', ''staff'', 999999)', :tea));
reset role;
select t.ok('إجمالي مشروب الاستاف 0 وسعر البند 0 والتكلفة 8', (select total = 0 from cafe_sales where id = :st) and (select unit_price = 0 and unit_cost = 4 and qty = 2 from cafe_sale_items where sale_id = :st));
select t.ok('المخزون نزل (50 - 1 - 2 - 3 - 2 = 42)', (select stock = 42 from cafe_products where id = :tea));
select t.ok('الدرج ما اتغيّرش بمشروب الاستاف', (day_figures(biz_today())->>'cash_sales')::numeric = :cash_before);
select t.as_(:'mgr');
select t.ok('التقرير: مشروب استاف 2 قطعة بتكلفة 8', (cafe_report(biz_today(), biz_today())->'staff_drinks'->>'qty')::int = 2 and (cafe_report(biz_today(), biz_today())->'staff_drinks'->>'cost')::numeric = 8);
select t.ok('التقرير: المبيعات 60 والطلبات 3 (من غير الاستاف) وتكلفة المباع بتشمل الاستاف', (cafe_report(biz_today(), biz_today())->>'sales')::numeric = 60 and (cafe_report(biz_today(), biz_today())->>'orders')::int = 3 and (cafe_report(biz_today(), biz_today())->>'cogs')::numeric = 4*(1+2+3+2));
select t.ok('الأكثر مبيعًا مايحسبش الاستاف (6 شاي)', (cafe_report(biz_today(), biz_today())->'top'->0->>'qty')::int = 6);
select t.ok('المدير يشوف مشروب الاستاف في آخر العمليات', exists (select 1 from jsonb_array_elements(cafe_recent_sales(30)) x where x->>'method' = 'staff'));
-- إلغاء مشروب الاستاف بيرجّع المخزون
select cafe_void_sale(:st, 'تجربة');
reset role;
select t.ok('الإلغاء رجّع المخزون (44)', (select stock = 44 from cafe_products where id = :tea));
rollback;
select 'ALL SHIFT+STAFF-DRINK TESTS PASSED';
