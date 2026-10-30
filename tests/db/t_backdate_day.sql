\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fails(n text, q text, part text default null) returns void language plpgsql as $$
begin begin execute q; exception when others then
  if part is not null and position(part in sqlerrm) = 0 then raise exception 'FAIL: % (رسالة مختلفة: %)', n, sqlerrm; end if; raise notice 'PASS: % [%]', n, sqlerrm; return; end;
  raise exception 'FAIL: % (المفروض يفشل)', n; end $$;
grant usage on schema t to public;
\set own '00000000-0000-0000-0000-0000000000a1'
\set b1 '00000000-0000-0000-0000-0000000000b1'
begin;
delete from business_days; delete from cash_closings where day >= current_date - 10;
select (biz_natural_day()) as nat \gset
-- 1) من غير أي يوم مفتوح: مفيش تأريخ
select t.ok('مفيش يوم مفتوح = مفيش تغيير', biz_shift_days() = 0);
-- 2) المالك يفتح يوم من يومين
select t.as_(:'own');
select open_business_day((:'nat'::date) - 2) as st \gset
select t.ok('اليوم اتفتح بتاريخه', (select (business_day_state()->>'day')::date = :'nat'::date - 2 and (business_day_state()->>'backdated')::boolean));
select t.ok('الفرق -2', biz_shift_days() = -2);
reset role;
-- سجلات جديدة (بتاخد وقت دلوقتي) لازم تتأرّخ بيوم الفتح
insert into invoices(id,no,subtotal,total,payment_method) values (992001,992001,100,100,'cash');
insert into expenses(category,amount,paid_from) values ('اختبار',30,'drawer');
insert into cash_moves(kind,amount) values ('deposit',50);
insert into staff_transactions(staff_id,kind,amount) values (:'b1','advance',20);
select t.ok('الفاتورة اتأرّخت بيوم الفتح', (select ((created_at at time zone my_tz()) - interval '6 hours')::date = :'nat'::date - 2 from invoices where id=992001));
select t.ok('وقت اليوم اتحفظ', (select abs(extract(epoch from ((created_at at time zone my_tz())::time - (now() at time zone my_tz())::time))) < 120 from invoices where id=992001));
select t.ok('المصروف اتأرّخ', (select count(*)=1 from expenses where category='اختبار' and spent_on = :'nat'::date - 2));
select t.ok('الضخ اتأرّخ', (select count(*)=1 from cash_moves where kind='deposit' and amount=50 and day = :'nat'::date - 2));
select t.ok('السلفة اتأرّخت', (select ((created_at at time zone my_tz()) - interval '6 hours')::date = :'nat'::date - 2 from staff_transactions where kind='advance' and amount=20 order by id desc limit 1));
-- سجل بتاريخ قديم مقصود ما بيتلمسش
insert into invoices(id,no,subtotal,total,payment_method,created_at) values (992002,992002,10,10,'cash', now() - interval '10 days');
select t.ok('فاتورة بتاريخ قديم مقصود ما اتغيرتش', (select created_at < now() - interval '9 days' from invoices where id=992002));
-- مصروف بتاريخ مختار بإيد المستخدم ما بيتلمسش
insert into expenses(category,amount,paid_from,spent_on) values ('اختبار2',5,'drawer', :'nat'::date - 5);
select t.ok('مصروف بتاريخ مختار ما اتغيرش', (select spent_on = :'nat'::date - 5 from expenses where category='اختبار2'));
-- التقارير: اليوم المفتوح فيه الفاتورة والمصروف والضخ والسلفة
select t.ok('الأرقام على اليوم المفتوح', (select (f->>'invoices')::int = 1 and (f->>'cash_sales')::numeric = 100 and (f->>'exp_cash')::numeric = 30 and (f->>'moves_in')::numeric = 50 and (f->>'adv_cash')::numeric = 20
   from (select day_figures(:'nat'::date - 2) f) x));
-- فتح يوم تاني وفيه يوم مفتوح مرفوض
select t.as_(:'own');
select t.fails('مينفعش يوم تاني وفيه مفتوح', format('select open_business_day(%L::date)', :'nat'::date - 1), 'فيه يوم مفتوح');
-- قفل اليوم القديم: وقت القفل يتأرّخ جوه اليوم ده
select close_day(:'nat'::date - 2, 100, 0, 0, 0, 'اختبار') as cl \gset
reset role;
update business_days set closed_at = closed_at + interval '1 minute' where day = :'nat'::date - 2; -- محاكاة مرور وقت بين الفاتورة والقفل
select t.ok('قفل اليوم متأرّخ بيومه', (select ((closed_at at time zone my_tz()) - interval '6 hours')::date = :'nat'::date - 2 from business_days where day = :'nat'::date - 2));
select t.ok('الجرد صفر فرق', (select diff_cash = 0 from cash_closings where day = :'nat'::date - 2));
select t.ok('بعد القفل مفيش تأريخ', biz_shift_days() = 0);
-- اليوم التالي: بعد آخر يوم
select t.as_(:'own');
select t.fails('يوم أقدم من آخر يوم مرفوض', format('select open_business_day(%L::date)', :'nat'::date - 3), 'اتعمله جرد');
select t.fails('يوم في المستقبل مرفوض', format('select open_business_day(%L::date)', (now() at time zone my_tz())::date + 2), 'لسه ما جاش');
select open_business_day(:'nat'::date - 1) as st2 \gset
select t.ok('اليوم اللي بعده اتفتح', (business_day_state()->>'day')::date = :'nat'::date - 1);
reset role;
insert into invoices(id,no,subtotal,total,payment_method) values (992003,992003,70,70,'cash');
select t.ok('فاتورة اليوم التاني اتأرّخت', (select ((created_at at time zone my_tz()) - interval '6 hours')::date = :'nat'::date - 1 from invoices where id=992003));
select t.ok('اليوم الأول ما اتأثرش (مفيش تداخل)', (day_figures(:'nat'::date - 2)->>'invoices')::int = 1 and (day_figures(:'nat'::date - 1)->>'invoices')::int = 1);
-- كاشير مايفتحش
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fails('الكاشير مايفتحش يوم', 'select open_business_day(current_date)', 'غير مصرح');
reset role;
rollback;
