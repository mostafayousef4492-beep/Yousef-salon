\set ON_ERROR_STOP 1
\set QUIET 1
-- اختبار patch_cafe_staff.sql (موظف الكوفي: بيع، آجل، تحصيل، سحب، مصروف). بيتشغّل بعد t_coffee_corner على نفس القاعدة المحلية.
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
\set cf '00000000-0000-0000-0000-0000000000c1'
\set cf2 '00000000-0000-0000-0000-0000000000c2'
begin;
insert into auth.users(id,email) values (:'mgr','mgr@t.t'),(:'cf','cf@t.t'),(:'cf2','cf2@t.t') on conflict do nothing;
insert into profiles(id, full_name, role) values (:'mgr','مدير','manager'),(:'cf','موظف كوفي','assistant'),(:'cf2','مساعد عادي','assistant') on conflict do nothing;
update profiles set perms = '{"use_cafe": true}'::jsonb where id = :'cf';
update profiles set perms = '{}'::jsonb where id in (:'cf2', :'cash', :'bar');
delete from business_days; delete from cash_closings where day >= current_date - 5;
delete from cash_moves; delete from staff_transactions;
update cafe_products set cost = 4, price = 10, track_stock = true, stock = 50 where name = 'شاي';
update cafe_products set cost = 8, price = 15, track_stock = false where name = 'نسكافيه';
select id as tea from cafe_products where name = 'شاي' \gset
select id as nes from cafe_products where name = 'نسكافيه' \gset

-- ===== الصلاحيات =====
select t.anon_();
select t.fl('زائر مايشوفش المنيو', 'select cafe_menu()');
select t.fl('زائر مايشوفش العملاء', 'select cafe_debtors()');
select t.fl('زائر مايسحبش', 'select cafe_add_withdrawal(''owner'', 10)');
select t.fl('زائر مايقراش جدول العملاء', 'select count(*) from cafe_customers');
reset role;
select t.as_(:'bar');
select t.fl('حلاق مايبيعش', format('select cafe_sell(''[{"id":%s,"qty":1}]'', ''cash'')', :tea));
select t.fl('حلاق مايسحبش', 'select cafe_add_withdrawal(''owner'', 10)');
reset role;
select t.as_(:'cf2');
select t.fl('مساعد من غير صلاحية مايشوفش المنيو', 'select cafe_menu()');
select t.fl('مساعد من غير صلاحية مايسجلش مصروف', 'select cafe_add_expense(null,''كهرباء'',5)');
reset role;
select t.as_(:'cf');
select t.ok('موظف الكوفي يشوف المنيو بدون تكلفة', cafe_menu()::text not like '%cost%' and jsonb_array_length(cafe_menu()) >= 8);
select t.fl('موظف الكوفي مايعدّلش منتج', 'select cafe_save_product(null,''x'',5,1,false,0,true)');
select t.fl('موظف الكوفي مايضيفش مشتريات', 'select cafe_record_purchase(current_date,''stock'',''[{"name":"x","qty":1,"unit_cost":5}]'',null,''drawer'',null)');
select t.fl('موظف الكوفي مايشوفش التقرير', 'select cafe_report(current_date,current_date)');
select t.fl('موظف الكوفي مايشوفش admin_lists', 'select cafe_admin_lists(current_date,current_date)');
select t.ok('RLS: موظف الكوفي مايشوفش صفوف الجداول', (select count(*) from cafe_sales) = 0 and (select count(*) from cafe_customers) = 0 and (select count(*) from cafe_withdrawals) = 0);
select t.fl('مايكتبش في cafe_debt_payments مباشرة', 'insert into cafe_debt_payments(debtor_id,amount) values (1,1)');
select t.fl('مايكتبش في cafe_withdrawals مباشرة', 'insert into cafe_withdrawals(kind,amount,ref_table) values (''owner'',1,''cash_moves'')');
reset role;
-- الكاشير القديم لسه شغّال (use_pos) من غير ما نلمس صلاحياته
select t.as_(:'cash');
select t.ok('الكاشير يشوف المنيو (توافق مع القديم)', jsonb_array_length(cafe_menu()) >= 8);
reset role;
-- مفتاح use_cafe=false بيقفل حتى الكاشير
update profiles set perms = '{"use_cafe": false}'::jsonb where id = :'cash';
select t.as_(:'cash');
select t.fl('الكاشير بعد قفل use_cafe مايبيعش', format('select cafe_sell(''[{"id":%s,"qty":1}]'', ''cash'')', :tea));
reset role;
update profiles set perms = '{}'::jsonb where id = :'cash';

-- ===== بيع كاش + مخزون =====
select t.as_(:'cf');
select cafe_sell(format('[{"id":%s,"qty":3},{"id":%s,"qty":1}]', :tea, :nes)::jsonb, 'cash') as s1 \gset
select t.fl('بيع آجل من غير عميل', format('select cafe_sell(''[{"id":%s,"qty":1}]'',''credit'')', :tea));
select t.fl('آجل لعميل مش موجود', format('select cafe_sell(''[{"id":%s,"qty":1}]'',''credit'',null,null,9999)', :tea));
select t.fl('طريقة دفع غلط', format('select cafe_sell(''[{"id":%s,"qty":1}]'',''x'')', :tea));
reset role;
select t.ok('الإجمالي 3×10+15 = 45 بسعر السيرفر', (select total from cafe_sales where id = :s1) = 45);
select t.ok('المخزون نزل 47', (select stock from cafe_products where id = :tea) = 47);

-- ===== عملاء الآجل =====
select t.as_(:'cf');
select cafe_debtor_save('  أحمد  ', '٠١٠٠١٢٣٤٥٦٧') as d1 \gset
select cafe_debtor_save('أحمد') as d1b \gset
select t.ok('نفس الاسم = نفس العميل', :d1 = :d1b);
select t.fl('اسم فاضي', 'select cafe_debtor_save(''   '')');
select t.fl('موبايل غلط', 'select cafe_debtor_save(''سعيد'', ''12'')');
select cafe_debtor_save('سعيد') as d2 \gset
reset role;
select t.ok('الموبايل اتخزّن بأرقام إنجليزي', (select phone from cafe_customers where id = :d1) = '01001234567');

-- بيع آجل
select t.as_(:'cf');
select cafe_sell(format('[{"id":%s,"qty":2},{"id":%s,"qty":2}]', :tea, :nes)::jsonb, 'credit', null, 'حساب', :d1) as c1 \gset
reset role;
select t.ok('الآجل 2×10+2×15 = 50', (select total from cafe_sales where id = :c1) = 50 and (select payment_method from cafe_sales where id = :c1) = 'credit');
select t.ok('الآجل مش في الدرج (كاش الكوفي لسه 45)', (day_figures(biz_today())->>'cafe_cash')::numeric = 45);
select t.fl('قيد: credit من غير عميل', 'insert into cafe_sales(payment_method,total) values (''credit'',1)');
select t.fl('قيد: cash مع عميل', format('insert into cafe_sales(payment_method,total,debtor_id) values (''cash'',1,%s)', :d1));
select t.as_(:'cf');
select cafe_debtors() as dl \gset
select t.ok('المتبقي على أحمد 50 والتليفون مخفي عن الموظف', (select (e->>'balance')::numeric = 50 and e->'phone' = 'null'::jsonb from jsonb_array_elements(:'dl'::jsonb) e where (e->>'id')::bigint = :d1));
reset role;
select t.as_(:'mgr');
select t.ok('المدير يشوف التليفون', (select e->>'phone' is not null from jsonb_array_elements(cafe_debtors()) e where (e->>'id')::bigint = :d1));
reset role;

-- ===== التحصيل =====
select t.as_(:'cf');
select t.fl('تحصيل صفر', format('select cafe_collect_debt(%s, 0)', :d1));
select t.fl('تحصيل أكتر من المتبقي', format('select cafe_collect_debt(%s, 51)', :d1));
select t.fl('تحصيل من عميل مفيش عليه', format('select cafe_collect_debt(%s, 5)', :d2));
select cafe_collect_debt(:d1, 20) as k1 \gset
reset role;
select max(id) as pay1 from cafe_debt_payments \gset
select t.ok('باقي 30 بعد تحصيل 20', cafe_debtor_balance(:d1) = 30);
select t.ok('التحصيل دخل الدرج كإضافة للدرج', (day_figures(biz_today())->>'moves_in')::numeric = 20 and (select count(*) from cash_moves where kind = 'deposit' and note like '[كوفي] تحصيل آجل%') = 1);
-- مينفعش تلغي البيع الآجل لو هيخلي الرصيد بالسالب
select t.as_(:'mgr');
select t.fl('إلغاء بيع آجل اتسدّد منه', format('select cafe_void_sale(%s)', :c1));
reset role;
-- تراجع التحصيل: موظف تاني مايقدرش، صاحب العملية يقدر
select t.as_(:'cf2');
select t.fl('موظف تاني مايلغيش التحصيل', format('select cafe_void_collection(%s)', :pay1));
reset role;
select t.as_(:'cf');
select cafe_void_collection(:pay1);
select t.fl('إلغاء التحصيل مرتين', format('select cafe_void_collection(%s)', :pay1));
reset role;
select t.ok('الرصيد رجع 50 وحركة الدرج اتشالت', cafe_debtor_balance(:d1) = 50 and not exists (select 1 from cash_moves where kind = 'deposit'));
select t.ok('اتسجّل في سجل المحذوفات', (select count(*) from deletion_log where table_name = 'cash_moves') = 1);
-- تحصيل كامل بعد كده
select t.as_(:'cf');
select cafe_collect_debt(:d1, 50, 'سدد كله') as k2 \gset
reset role;
select max(id) as pay2 from cafe_debt_payments \gset
select t.ok('الرصيد صفر', cafe_debtor_balance(:d1) = 0);
-- تحصيل قديم (أكتر من 30 دقيقة): الموظف مايلغيهوش، المالك يلغيه
update cafe_debt_payments set created_at = now() - interval '2 hours' where id = (select max(id) from cafe_debt_payments);
select t.as_(:'cf');
select t.fl('موظف مايلغيش تحصيل قديم', format('select cafe_void_collection(%s)', :pay2));
reset role;
select t.as_(:'own');
select cafe_void_collection(:pay2);
reset role;
select t.ok('المالك لغى القديم والرصيد 50', cafe_debtor_balance(:d1) = 50);
-- إلغاء بيع آجل بعد ما الدين اتشال: يتلغي عادي ويرجّع المخزون
select t.as_(:'mgr');
select cafe_void_sale(:c1, 'غلط');
reset role;
select t.ok('إلغاء الآجل صفّر الرصيد ورجّع المخزون', cafe_debtor_balance(:d1) = 0 and (select stock from cafe_products where id = :tea) = 47);

-- ===== السحب =====
select t.as_(:'cf');
select t.fl('نوع سحب غلط', 'select cafe_add_withdrawal(''x'', 10)');
select t.fl('سحب صفر', 'select cafe_add_withdrawal(''owner'', 0)');
select t.fl('سحب سالب', 'select cafe_add_withdrawal(''owner'', -5)');
select t.fl('سبب آخر من غير سبب', 'select cafe_add_withdrawal(''other'', 10)');
select t.fl('موظف يسحب أكتر من الحد', 'select cafe_add_withdrawal(''owner'', 100001)');
select cafe_add_withdrawal('owner', 100, 'للمالك') as w1 \gset
select cafe_add_withdrawal('advance', 40) as w2 \gset
select cafe_add_withdrawal('other', 7, 'فكة') as w3 \gset
reset role;
select t.ok('سحب المالك نزل الدرج (moves_out=107) والسلفة في staff_transactions',
  (day_figures(biz_today())->>'moves_out')::numeric = 107 and (day_figures(biz_today())->>'adv_cash')::numeric = 40
  and (select staff_id from staff_transactions where kind = 'advance') = :'cf'::uuid);
select t.ok('الملاحظة فيها اسم الموظف', exists (select 1 from cash_moves where kind = 'withdraw' and note like '[كوفي] سحب للمالك%موظف كوفي%'));
select t.as_(:'cf2');
select t.fl('موظف تاني مايلغيش سحب', format('select cafe_void_withdrawal(%s)', (:'w1'::jsonb->>'id')::bigint));
reset role;
select t.as_(:'cf');
select cafe_void_withdrawal((:'w2'::jsonb->>'id')::bigint);
select cafe_void_withdrawal((:'w3'::jsonb->>'id')::bigint);
select t.fl('إلغاء السحب مرتين', format('select cafe_void_withdrawal(%s)', (:'w3'::jsonb->>'id')::bigint));
reset role;
select t.ok('إلغاء السلفة شالها من staff_transactions وإلغاء السحب شاله من cash_moves',
  not exists (select 1 from staff_transactions where kind = 'advance') and (select count(*) from cash_moves where kind = 'withdraw') = 1);
-- سلفة المالك نفسه مرفوضة
select t.as_(:'own');
select t.fl('المالك مالوش سلفة', 'select cafe_add_withdrawal(''advance'', 10)');
reset role;

-- ===== المصروفات =====
select t.as_(:'cf');
select t.fl('مصروف صفر', 'select cafe_add_expense(null,''كهرباء'',0)');
select t.fl('مصروف بدون تصنيف', 'select cafe_add_expense(null,'' '',5)');
select t.fl('الموظف مايسجلش من برّه الدرج', 'select cafe_add_expense(null,''كهرباء'',5,null,''other'')');
select t.fl('الموظف فوق الحد', 'select cafe_add_expense(null,''كهرباء'',100001)');
select cafe_add_expense(current_date - 3, 'مستلزمات', 25, 'سكر') as e1 \gset
reset role;
select t.ok('التاريخ اتفرض يوم العمل مش اللي الموظف بعته', (select spent_on from cafe_expenses where id = :e1) = biz_today());
select t.ok('المصروف نزل من الدرج', (day_figures(biz_today())->>'cafe_exp_cash')::numeric = 25);
select t.as_(:'cf2');
select t.fl('موظف تاني مايمسحش المصروف', format('select cafe_delete_expense(%s)', :e1));
reset role;
select t.as_(:'cf');
select cafe_add_expense(null, 'أخرى', 9) as e2 \gset
select cafe_delete_expense(:e2);
reset role;
select t.ok('الموظف مسح مصروفه الأخير', not exists (select 1 from cafe_expenses where id = :e2));
update cafe_expenses set created_at = now() - interval '2 hours' where id = :e1;
select t.as_(:'cf');
select t.fl('موظف مايمسحش مصروف قديم', format('select cafe_delete_expense(%s)', :e1));
reset role;
select t.as_(:'own');
select cafe_delete_expense(:e1);
reset role;
select t.ok('المالك يمسح القديم', not exists (select 1 from cafe_expenses where id = :e1));
-- مدير يسجّل مصروف بتاريخ ومن برّه الدرج زي الأول
select t.as_(:'mgr');
select cafe_add_expense(current_date - 1, 'كهرباء', 60, 'فاتورة', 'other') as e3 \gset
reset role;
select t.ok('المدير بيحدد التاريخ ومصدر الدفع', (select spent_on = current_date - 1 and paid_from = 'other' from cafe_expenses where id = :e3));

-- ===== اليوم المقفول =====
insert into cash_closings(day,opening,expected_cash,expected_card,expected_wallet,counted_cash,counted_card,counted_wallet,diff_cash,diff_card,diff_wallet) values (biz_today(),0,0,0,0,0,0,0,0,0,0);
select t.as_(:'cf');
select t.fl('مصروف بعد القفل', 'select cafe_add_expense(null,''كهرباء'',5)');
select t.fl('سحب بعد القفل', 'select cafe_add_withdrawal(''owner'', 5)');
select t.fl('تحصيل بعد القفل', format('select cafe_collect_debt(%s, 1)', :d1));
reset role;
delete from cash_closings where day = biz_today();

-- ===== حركة اليوم =====
select t.as_(:'cf');
select cafe_sell(format('[{"id":%s,"qty":1}]', :tea)::jsonb, 'card') as s9 \gset
select cafe_staff_day() as dayj \gset
reset role;
select t.ok('حركة اليوم للموظف: اللي سجّله هو بس', (:'dayj'::jsonb->>'scope') = 'mine' and (:'dayj'::jsonb->'sales'->>'orders')::int = 2 and (:'dayj'::jsonb->'sales'->>'card')::numeric = 10);
select t.as_(:'cash');
select t.ok('كاشير مايشوفش مبيعات موظف الكوفي', (cafe_staff_day()->'sales'->>'orders')::int = 0);
reset role;
select t.as_(:'mgr');
select t.ok('المدير يشوف الكل', (cafe_staff_day()->>'scope') = 'all' and (cafe_staff_day()->'sales'->>'orders')::int = 2);
reset role;

-- ===== التقرير =====
select t.as_(:'own');
select cafe_sell(format('[{"id":%s,"qty":2}]', :tea)::jsonb, 'credit', null, null, :d2) as c2 \gset
select cafe_collect_debt(:d2, 5, null) as k3 \gset
select cafe_report(biz_today(), biz_today()) as rp \gset
reset role;
select t.ok('تقرير: الآجل 20 والتحصيل 5 والمستحق 15', (:'rp'::jsonb->>'credit_sales')::numeric = 20 and (:'rp'::jsonb->>'debt_collected')::numeric = 5 and (:'rp'::jsonb->>'outstanding_debt')::numeric = 15);
select t.ok('تقرير: السحب 100 (الملغي مستبعد)', (:'rp'::jsonb->>'withdrawals')::numeric = 100);
select t.ok('تقرير: المبيعات 45+10+20 والآجل جواها', (:'rp'::jsonb->>'sales')::numeric = 75 and (:'rp'::jsonb->'by_method'->>'credit')::numeric = 20);
select t.ok('تقرير: صافي الربح = مبيعات - تكلفة - مصروفات (السحب مش مصروف)', (:'rp'::jsonb->>'net_profit')::numeric = 75 - (3*4+8 + 4 + 2*4) - 0);
select t.ok('تقرير: أكبر مدين', :'rp'::jsonb->'top_debtors'->0->>'name' = 'سعيد');
-- مفاتيح التقرير القديمة لسه موجودة
select t.ok('مفاتيح التقرير القديمة لسه موجودة', (:'rp'::jsonb) ?& array['sales','salon_sales','street_sales','orders','cogs','purchases','expenses','net_profit','by_method','top','by_day','expenses_by_category','low_stock']);
rollback;
\echo ALL CAFE STAFF TESTS DONE
