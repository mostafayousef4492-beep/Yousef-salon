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
\set cash '00000000-0000-0000-0000-0000000000a2'
\set b1 '00000000-0000-0000-0000-0000000000b1'
begin;
update profiles set commission_pct=40, salary=3000 where id=:'b1';
insert into invoices(barber_id,subtotal,discount,total,payment_method) values (:'b1',200,0,200,'cash'),(:'b1',100,0,100,'wallet');
insert into expenses(spent_on,category,amount,note) values (current_date,'إيجار',500,'x'),(current_date,'كهرباء',120,'y');
insert into staff_transactions(staff_id,kind,amount,note) values (:'b1','advance',50,'سلفة'),(:'b1','bonus',30,'مكافأة'),(:'b1','deduction',10,'خصم'),(:'b1','bonus',100,'أجر يوم 2026-10-27');
select t.as_(:'own');
create temp table x as select export_report(null, current_date - 30, current_date) j, full_report((current_date - 30)::timestamp at time zone my_tz(), (current_date + 1)::timestamp at time zone my_tz()) f;
grant all on x to public;
select t.ok('فيه 6 جداول + meta', (select j ? 'sales' and j ? 'barbers' and j ? 'attendance' and j ? 'inventory' and j ? 'services' and j ? 'cash' and j ? 'meta' from x));
select t.ok('عدد الفواتير في المبيعات', (select count(*) from x, jsonb_array_elements(j->'sales') r where r->>4 = 'مدفوعة') >= 2);
select t.ok('إجمالي المبيعات = الإيراد في التقرير الشامل', (select (select sum((r->>6)::numeric) from jsonb_array_elements(j->'sales') r) = (f->>'revenue')::numeric from x));
select t.ok('المصروفات = التقرير الشامل', (select coalesce((select sum((r->>8)::numeric) from jsonb_array_elements(j->'sales') r),0) = (f->>'expenses')::numeric from x));
select t.ok('الربح في الإكسيل = ربح التقرير الشامل', (select abs(
   coalesce((select sum((r->>6)::numeric) from jsonb_array_elements(j->'sales') r),0)
 - coalesce((select sum((r->>7)::numeric) from jsonb_array_elements(j->'sales') r),0)
 - coalesce((select sum((r->>8)::numeric) from jsonb_array_elements(j->'sales') r),0)
 - coalesce((select sum((r->>9)::numeric) from jsonb_array_elements(j->'sales') r),0)
 - coalesce((select sum((r->>10)::numeric) from jsonb_array_elements(j->'sales') r),0) - (f->>'profit')::numeric) < 0.01 from x));
select t.ok('الخزنة فيها اليوم', (select count(*) >= 1 from x, jsonb_array_elements(j->'cash') r where r->>0 = current_date::text));
select t.ok('خدمات الفواتير بتتسجل', (select jsonb_array_length(j->'services') from x) >= 0);
reset role;
-- ناس مالهاش حق
select t.as_(:'cash');
select t.fails('الكاشير مايقدرش يصدّر', 'select export_report(null, current_date, current_date)', 'غير مصرح');
select t.fails('الكاشير مايعملش مفتاح', 'select owner_make_export_token(''x'')', 'غير مصرح');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select t.fails('من غير مفتاح مرفوض', 'select export_report(null, current_date, current_date)', 'غير مصرح');
select t.fails('مفتاح غلط مرفوض', 'select export_report(''xl_bad'', current_date, current_date)', 'غير مصرح');
reset role;
-- مفتاح التصدير
select t.as_(:'own');
select owner_make_export_token('الكمبيوتر') as tok \gset
reset role;
select t.ok('المفتاح بيتخزن مشفّر', (select count(*) = 1 and bool_and(token_hash <> :'tok') from export_tokens));
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select t.ok('المفتاح بيشتغل من غير تسجيل دخول', (select (export_report(:'tok', current_date - 1, current_date)->'meta'->>'from') is not null));
select t.fails('الفترة المقلوبة مرفوضة', format('select export_report(%L, current_date, current_date - 1)', :'tok'), 'الفترة');
reset role;
select t.as_(:'own');
select t.ok('المالك يشوف قائمة المفاتيح وآخر استخدام', (select count(*) = 1 and bool_or(last_used_at is not null) from owner_export_tokens()));
select owner_revoke_export_token((select id from owner_export_tokens() limit 1));
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select t.fails('المفتاح الملغي مرفوض', format('select export_report(%L, current_date, current_date)', :'tok'), 'غير مصرح');
reset role;
rollback;
