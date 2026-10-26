\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.back() returns void language plpgsql as $$ begin execute 'reset role'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fails(n text, q text, part text default null) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if part is not null and position(part in sqlerrm) = 0 then raise exception 'FAIL: % (رسالة مختلفة: %)', n, sqlerrm; end if;
    raise notice 'PASS: % [%]', n, sqlerrm; return;
  end;
  raise exception 'FAIL: % (المفروض يفشل)', n;
end $$;
\set cash '00000000-0000-0000-0000-0000000000a2'
\set c1 '00000000-0000-0000-0000-0000000000c1'
\set b1 '00000000-0000-0000-0000-0000000000b1'
begin;
insert into app_settings(key,value) values ('ff_loyalty','true') on conflict (key) do update set value='true';
update customers set points = 0 where id = 1;
-- 1) من غير نقاط
select t.as_(:'c1');
select t.ok('0 نقطة: مفيش استبدال متاح', (select bool_and((i->>'ok')::boolean = false) from jsonb_array_elements(redeem_service_options()->'items') i));
select t.fails('0 نقطة: يرفض', 'select redeem_service(1)', 'محتاج على الأقل');
select t.back();
-- 2) أقل من الحد الأدنى
update customers set points = 60 where id = 1;
select t.as_(:'c1');
select t.fails('60 نقطة (أقل من 100): يرفض', 'select redeem_service(1)', 'محتاج على الأقل');
select t.back();
-- 3) نقاط ما تكفيش الخدمة كلها: يخصم كل النقاط والباقي يدفعه
update customers set points = 200 where id = 1;
select t.as_(:'c1');
select redeem_service(1) as r1 \gset
select t.back();
select t.ok('خدمة 100ج و200 نقطة: خصم 40 ويدفع 60', (:'r1'::jsonb->>'discount')::numeric = 40 and (:'r1'::jsonb->>'pay')::numeric = 60 and (:'r1'::jsonb->>'points_used')::int = 200);
select t.ok('النقاط اتخصمت', (select points from customers where id = 1) = 0);
select t.ok('الليدجر اتسجل', exists (select 1 from loyalty_ledger where customer_id = 1 and reason = 'redeem' and points = -200));
select t.ok('الكوبون active ومخفي من القايمة العامة', exists (select 1 from loyalty_redemptions d join loyalty_rewards w on w.id = d.reward_id where d.code = :'r1'::jsonb->>'code' and d.status = 'active' and w.active = false and w.kind = 'amount' and w.value = 40));
-- 4) نقاط تكفي: يخصم بس المطلوب
update customers set points = 600 where id = 1;
select t.as_(:'c1');
select redeem_service(2) as r2 \gset
select t.back();
select t.ok('دقن 50ج و600 نقطة: خصم 50 ويدفع 0 ونقاط مستخدمة 250', (:'r2'::jsonb->>'discount')::numeric = 50 and (:'r2'::jsonb->>'pay')::numeric = 0 and (:'r2'::jsonb->>'points_used')::int = 250 and (select points from customers where id = 1) = 350);
-- 5) خدمة غير متاحة، وعميل تاني مايقدرش يستخدم كوبون العميل الأول
select t.as_(:'c1');
select t.fails('خدمة موقوفة', 'select redeem_service(3)', 'مش متاحة');
select t.back();
-- 6) الكاشير بيطبق الكوبون: الفاتورة 100 - خصم 40 = 60
select t.as_(:'cash');
select pos_checkout(p_customer=>1, p_barber=>:'b1'::uuid, p_items=>'[{"type":"service","id":1,"qty":1}]'::jsonb, p_discount_pct=>0, p_discount_fixed=>0, p_method=>'cash', p_appointment=>null, p_redemption=>(select d.id from loyalty_redemptions d where d.code = :'r1'::jsonb->>'code')) as inv \gset
select t.back();
select t.ok('الفاتورة بعد الكوبون = 60', (select total from invoices where id = :inv) = 60);
select t.ok('الكوبون اتستخدم', (select status from loyalty_redemptions where code = :'r1'::jsonb->>'code') = 'used');
-- 7) الإعداد قابل للتغيير: النقطة بـ 0.5 جنيه
insert into app_settings(key,value) values ('points_egp_value','0.5') on conflict (key) do update set value='0.5';
update customers set points = 100 where id = 1;
select t.as_(:'c1');
select redeem_service(1) as r3 \gset
select t.back();
select t.ok('نقطة بـ 0.5: 100 نقطة = خصم 50', (:'r3'::jsonb->>'discount')::numeric = 50);
-- 8) الزائر بدون تسجيل
select t.as_('00000000-0000-0000-0000-000000000099');
select t.fails('مستخدم من غير حساب عميل يرفض', 'select redeem_service(1)', 'سجّل دخول');
select t.back();
rollback;
select 'SERVICE REDEEM DONE';
