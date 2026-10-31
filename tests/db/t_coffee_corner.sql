\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.anon_() returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS: % [%]', n, sqlerrm; return; end; raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set cash '00000000-0000-0000-0000-0000000000a2'
\set bar '00000000-0000-0000-0000-0000000000b1'
\set mgr '00000000-0000-0000-0000-0000000000a3'
begin;
insert into auth.users(id,email) values (:'mgr','mgr@t.t') on conflict do nothing;
insert into profiles(id, full_name, role) values (:'mgr', 'مدير', 'manager') on conflict do nothing;
delete from business_days; delete from cash_closings where day >= current_date - 5;
update cafe_products set cost = 4 where name = 'شاي';
update cafe_products set cost = 8 where name = 'نسكافيه';
select id as tea from cafe_products where name = 'شاي' \gset
select id as nes from cafe_products where name = 'نسكافيه' \gset

-- المنتجات الابتدائية
select t.ok('8 منتجات ابتدائية', (select count(*) from cafe_products) = 8);

-- صلاحيات
select t.anon_();
select t.fl('زائر مايشوفش المنيو', 'select cafe_menu()');
select t.fl('زائر مايبيعش', format('select cafe_sell(''[{"id":%s,"qty":1}]'', ''cash'')', :tea));
select t.fl('زائر مايقراش الجدول', 'select count(*) from cafe_sales');
reset role;
select t.as_(:'bar');
select t.fl('حلاق مايبيعش', format('select cafe_sell(''[{"id":%s,"qty":1}]'', ''cash'')', :tea));
select t.fl('حلاق مايشوفش المنيو', 'select cafe_menu()');
reset role;
select t.as_(:'cash');
select t.ok('كاشير يشوف المنيو من غير تكلفة', cafe_menu()::text not like '%cost%' and jsonb_array_length(cafe_menu()) = 8);
select t.fl('كاشير مايعدّلش منتج', 'select cafe_save_product(null,''x'',5,1,false,0,true)');
select t.fl('كاشير مايضيفش مشتريات', 'select cafe_record_purchase(current_date,''stock'',''[{"name":"x","qty":1,"unit_cost":5}]'',null,''drawer'',null)');
select t.fl('كاشير مايضيفش مصروف كوفي', 'select cafe_add_expense(current_date,''كهرباء'',5)');
select t.fl('كاشير مايشوفش التقرير', 'select cafe_report(current_date,current_date)');
select t.ok('كاشير مايشوفش صفوف الجدول (RLS)', (select count(*) from cafe_sales) = 0 and (select count(*) from cafe_products) = 0);
select t.fl('كاشير مايكتبش في الجدول مباشرة', 'insert into cafe_sales(payment_method,total) values (''cash'',1)');
select t.fl('كاشير مايعدّلش سعر مباشرة', 'update cafe_products set price = 1');
reset role;

-- بيع شارع (كاشير) + تتبع مخزون
select t.as_(:'own');
select cafe_save_product(:tea, 'شاي', 10, 4, true, 3, true, 1);
reset role;
select t.as_(:'mgr');
select cafe_adjust_stock(:tea, 10, 'جرد') as s \gset
select t.ok('مدير ضاف مخزون', :s = 10);
select t.fl('مخزون بالسالب', format('select cafe_adjust_stock(%s,-50)', :tea));
reset role;
select t.as_(:'cash');
select cafe_sell(format('[{"id":%s,"qty":3},{"id":%s,"qty":1}]', :tea, :nes)::jsonb, 'cash') as s1 \gset
select t.fl('مخزون مش كفاية', format('select cafe_sell(''[{"id":%s,"qty":8}]'',''cash'')', :tea));
select t.fl('طريقة دفع غلط', format('select cafe_sell(''[{"id":%s,"qty":1}]'',''x'')', :tea));
select t.fl('كمية صفر', format('select cafe_sell(''[{"id":%s,"qty":0}]'',''cash'')', :tea));
reset role;
select t.ok('الإجمالي بسعر السيرفر 3×10+15', (select total from cafe_sales where id = :s1) = 45);
select t.ok('المخزون نزل 7', (select stock from cafe_products where id = :tea) = 7);
select t.ok('نسكافيه من غير تتبع مافيش خصم', (select stock from cafe_products where id = :nes) = 0);
select t.ok('تكلفة وقت البيع متسجلة', (select sum(qty*unit_cost) from cafe_sale_items where sale_id = :s1) = 3*4+8);

-- إلغاء بيع: الكاشير صاحب العملية خلال 30 دقيقة
select t.as_(:'cash');
select cafe_void_sale(:s1, 'غلط');
select t.fl('إلغاء مرتين', format('select cafe_void_sale(%s)', :s1));
reset role;
select t.ok('الإلغاء رجّع المخزون', (select stock from cafe_products where id = :tea) = 10);
select t.ok('العملية الملغاة مش في الدرج', (day_figures(biz_today())->>'cafe_cash')::numeric = 0);

-- فاتورة صالون + مشروب: العمولة والإجمالي ما يتأثروش
update profiles set commission_pct = 40 where id = :'bar';
select t.as_(:'cash');
select pos_checkout(null, :'bar', '[{"type":"service","id":1,"qty":1}]'::jsonb, 0, 0, 'cash') as inv_plain \gset
select pos_checkout_cafe(null, :'bar', '[{"type":"service","id":1,"qty":1}]'::jsonb, 0, 0, 'cash', null, null, null,
  format('[{"id":%s,"qty":2}]', :tea)::jsonb) as inv_cafe \gset
reset role;
select t.ok('إجمالي الفاتورة = الخدمة بس', (select total from invoices where id = :inv_cafe) = (select total from invoices where id = :inv_plain));
select t.ok('بنود الفاتورة مفيهاش مشروب', (select count(*) from invoice_items where invoice_id = :inv_cafe) = (select count(*) from invoice_items where invoice_id = :inv_plain));
select t.ok('مبيعات الكوفي مربوطة بالفاتورة 20', (select total from cafe_sales where invoice_id = :inv_cafe) = 20);
select t.ok('المخزون نزل 2', (select stock from cafe_products where id = :tea) = 8);

-- الدرج الواحد
select t.ok('الدرج فيه الكاش (خدمتين + مشروب)', (day_figures(biz_today())->>'cash_sales')::numeric = (select sum(total) from invoices) + 20
  and (day_figures(biz_today())->>'cafe_cash')::numeric = 20);

-- مشتريات
select t.as_(:'mgr');
select cafe_record_purchase(biz_today(), 'stock', format('[{"product_id":%s,"qty":20,"unit_cost":5}]', :tea)::jsonb, 'مورد', 'drawer', 'بضاعة', true) as p1 \gset
select cafe_record_purchase(biz_today(), 'supplies', '[{"name":"أكواب","qty":10,"unit_cost":2}]'::jsonb, null, 'drawer', null) as p2 \gset
select cafe_record_purchase(biz_today(), 'supplies', '[{"name":"سكر","qty":1,"unit_cost":30}]'::jsonb, null, 'other', null) as p3 \gset
select t.fl('بند بكمية صفر', 'select cafe_record_purchase(current_date,''stock'',''[{"name":"x","qty":0,"unit_cost":5}]'',null,''drawer'',null)');
select t.fl('نوع غلط', 'select cafe_record_purchase(current_date,''x'',''[{"name":"x","qty":1,"unit_cost":5}]'',null,''drawer'',null)');
select cafe_add_expense(biz_today(), 'كهرباء', 50, 'فاتورة', 'drawer') as e1 \gset
select t.fl('مصروف صفر', 'select cafe_add_expense(current_date,''كهرباء'',0)');
reset role;
select t.ok('مشتريات البضاعة زوّدت المخزون 28', (select stock from cafe_products where id = :tea) = 28);
select t.ok('تحديث التكلفة', (select cost from cafe_products where id = :tea) = 5);
select t.ok('مشتريات المستلزمات عملت مصروف مربوط', (select amount from cafe_expenses where purchase_id = :p2) = 20);
select t.ok('مشتريات البضاعة مش مصروف', not exists (select 1 from cafe_expenses where purchase_id = :p1));

-- الدرج بعد المشتريات والمصروفات: بضاعة 100 (من الدرج) + مصروف 50؛ المستلزمات 20 بتتحسب مرة واحدة
-- (المشتريات 'drawer' بتروح في pur_cash، ومصروف المستلزمات المرتبط مش بيتعد تاني)
select t.ok('pur_cash بيشمل مشتريات الكوفي من الدرج مرة واحدة',
  (day_figures(biz_today())->>'cafe_pur_cash')::numeric = 100 + 20 and (day_figures(biz_today())->>'cafe_exp_cash')::numeric = 50);

-- التقرير
select t.as_(:'mgr');
select cafe_report(biz_today(), biz_today()) as rp \gset
reset role;
select t.ok('تقرير: مبيعات 20 (الملغي مستبعد)', (:'rp'::jsonb->>'sales')::numeric = 20 and (:'rp'::jsonb->>'salon_sales')::numeric = 20 and (:'rp'::jsonb->>'street_sales')::numeric = 0);
select t.ok('تقرير: تكلفة 2×4=8 (التكلفة وقت البيع)', (:'rp'::jsonb->>'cogs')::numeric = 8);
select t.ok('تقرير: مصروفات 50+20+30 = 100', (:'rp'::jsonb->>'expenses')::numeric = 100);
select t.ok('تقرير: صافي الربح 20-8-100 والمشتريات مش بتتخصم', (:'rp'::jsonb->>'net_profit')::numeric = -88 and (:'rp'::jsonb->>'purchases')::numeric = 100 + 20 + 30);
select t.ok('تقرير: الأكتر مبيعًا', :'rp'::jsonb->'top'->0->>'name' = 'شاي');

-- مسح مشتريات: المالك بس
select t.as_(:'mgr');
select t.fl('المدير مايلغيش مشتريات', format('select cafe_void_purchase(%s)', :p2));
select t.fl('المدير مايمسحش مصروف', format('select cafe_delete_expense(%s)', :e1));
reset role;
select t.as_(:'own');
select t.fl('مصروف تابع لمشتريات مايتمسحش لوحده', format('select cafe_delete_expense((select id from cafe_expenses where purchase_id = %s))', :p2));
select cafe_void_purchase(:p2);
select cafe_delete_expense(:e1);
select cafe_void_purchase(:p1);
reset role;
select t.ok('إلغاء الشراء مسح المصروف المرتبط', not exists (select 1 from cafe_expenses where purchase_id = :p2));
select t.ok('إلغاء شراء البضاعة رجّع المخزون', (select stock from cafe_products where id = :tea) = 8);
select t.ok('اتسجل في سجل المحذوفات', (select count(*) from deletion_log where table_name in ('cafe_purchases','cafe_expenses')) = 3);

-- مسح فاتورة الصالون: مشروب الفاتورة يتمسح ومفيش إيراد مكرر
select t.as_(:'own');
select admin_void_invoice(:inv_cafe::text, true);
reset role;
select t.ok('مسح الفاتورة مسح مبيعات الكوفي المربوطة', not exists (select 1 from cafe_sales where invoice_id = :inv_cafe));
select t.ok('المخزون رجع 10', (select stock from cafe_products where id = :tea) = 10);
select t.ok('الدرج مفيهوش إيراد الكوفي', (day_figures(biz_today())->>'cafe_cash')::numeric = 0);

-- تغيير تاريخ فاتورة بيحرّك مبيعات الكوفي معاها
select t.as_(:'cash');
select pos_checkout_cafe(null, :'bar', '[{"type":"service","id":1,"qty":1}]'::jsonb, 0, 0, 'cash', null, null, null,
  format('[{"id":%s,"qty":1}]', :tea)::jsonb) as inv2 \gset
reset role;
select t.as_(:'own');
select admin_set_date('invoice', :inv2::text, now() - interval '2 days', true);
reset role;
select t.ok('تاريخ مبيعات الكوفي اتحرّك مع الفاتورة', (select (created_at at time zone my_tz())::date from cafe_sales where invoice_id = :inv2) = (now() at time zone my_tz())::date - 2);

-- قفل اليوم بيحسب الكوفي
select t.as_(:'cash');
select cafe_sell(format('[{"id":%s,"qty":2}]', :tea)::jsonb, 'card') as s5 \gset
reset role;
select t.ok('الكارت اتحسب في الدرج', (day_figures(biz_today())->>'card_sales')::numeric >= 20);

-- تقرير بتواريخ غلط
select t.as_(:'own');
select t.fl('مدى غلط', 'select cafe_report(current_date, current_date - 1)');
reset role;
rollback;
\echo ALL COFFEE CORNER TESTS DONE
