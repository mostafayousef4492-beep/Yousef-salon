\set ON_ERROR_STOP 1
\set QUIET 1
create schema if not exists t;
create or replace function t.as_(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub',u,true); execute 'set local role authenticated'; end $$;
create or replace function t.ok(n text, c boolean) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', n; end if; raise notice 'PASS: %', n; end $$;
create or replace function t.fl(n text, q text) returns void language plpgsql as $$ begin begin execute q; exception when others then raise notice 'PASS (rejected): % [%]', n, sqlerrm; return; end; raise exception 'FAIL (no error): %', n; end $$;
grant usage on schema t to public;
\i sql/patch_bonus_paid.sql
create or replace function t.today() returns date language sql stable as $$ select (now() at time zone my_tz())::date $$;
grant execute on function t.today() to public;
create or replace function t.sal(d date) returns numeric language sql security definer as $$ select (range_figures_salon(d, d)->>'sal_cash')::numeric $$;
grant execute on function t.sal(date) to public;
begin;
update profiles set salary=0, commission_pct=0 where id='00000000-0000-0000-0000-0000000000b1';
create temp table b as select range_figures_salon(t.today(), t.today()) j, (staff_statement('00000000-0000-0000-0000-0000000000b1', null, now()+interval '1 day')->>'closing')::numeric c; grant all on b to public;
select t.as_('00000000-0000-0000-0000-0000000000a1');
-- 1) مكافأة 100 من غير صرف: الحساب +100، الدرج مش بيتأثر (السلوك القديم)
select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 100, 'مكافأة أ', false) as r1 \gset
select t.ok('بدون صرف: مفيش دفعة', (:'r1'::jsonb->'payment_id') = 'null'::jsonb and not (:'r1'::jsonb->>'paid_from_drawer')::boolean);
select t.ok('بدون صرف: الدرج ثابت', (select t.sal(t.today()) = (select (j->>'sal_cash')::numeric from b)));
select t.ok('بدون صرف: رصيد الموظف +100', (select (staff_statement('00000000-0000-0000-0000-0000000000b1', null, now()+interval '1 day')->>'closing')::numeric = (select c from b) + 100));
-- 2) مكافأة 40 مصروفة دلوقتي: الدرج -40، رصيد الموظف زي ما هو (اتدفعله)
select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 40, 'مكافأة ب', true) as r2 \gset
select t.ok('مع صرف: اتسجلت دفعة', (:'r2'::jsonb->>'payment_id') is not null and (:'r2'::jsonb->>'paid_from_drawer')::boolean);
select t.ok('مع صرف: الدرج نزل 40', (select t.sal(t.today()) = (select (j->>'sal_cash')::numeric from b) + 40));
select t.ok('مع صرف: رصيد الموظف لسه +100 بس (الـ40 اتدفعت)', (select (staff_statement('00000000-0000-0000-0000-0000000000b1', null, now()+interval '1 day')->>'closing')::numeric = (select c from b) + 100));
select t.ok('المكافأة والدفعة نفس المبلغ والموظف', (select count(*) = 1 from staff_transactions x join salary_payments p on p.staff_id = x.staff_id and p.amount = x.amount where x.id = (:'r2'::jsonb->>'tx_id')::bigint and p.id = (:'r2'::jsonb->>'payment_id')::bigint and p.paid_from = 'drawer'));
select t.ok('ملاحظة الصرف بتذكر المكافأة', (select note like 'صرف مكافأة%ب' from salary_payments where id = (:'r2'::jsonb->>'payment_id')::bigint));
-- 3) مكافأة قديمة (امبارح) مصروفة: الدفعة على امبارح مش النهارده
select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 25, null, true, t.today() - 1) as r3 \gset
select t.ok('قديمة: الدفعة paid_on امبارح', (select paid_on = t.today() - 1 from salary_payments where id = (:'r3'::jsonb->>'payment_id')::bigint));
select t.ok('قديمة: الدرج النهارده ماتأثرش بيها', (select t.sal(t.today()) = (select (j->>'sal_cash')::numeric from b) + 40));
select t.ok('قديمة: الدرج امبارح نزل 25', (select t.sal(t.today() - 1) >= 25));
-- 4) الرفض
select t.fl('مبلغ صفر', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 0, null, true)$$);
select t.fl('مبلغ سالب', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', -5, null, true)$$);
select t.fl('تاريخ في المستقبل', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 5, null, true, t.today() + 2)$$);
select t.fl('موظف مش موجود', $$select staff_bonus_add('00000000-0000-0000-0000-00000000ffff', 5, null, true)$$);
select t.fl('عميل مش موظف', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000c1', 5, null, true)$$);
select t.ok('الفشل مافيش منه أثر جزئي: مفيش مكافأة 5', (select count(*) = 0 from staff_transactions where amount = 5 and kind = 'bonus'));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('الكاشير مرفوض', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 5, null, true)$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مايقدرش يديلنفسه مكافأة', $$select staff_bonus_add('00000000-0000-0000-0000-0000000000b1', 5, null, true)$$);
reset role;
select t.ok('anon مالوش execute', not has_function_privilege('anon','staff_bonus_add(uuid,numeric,text,boolean,date)','execute'));
rollback;
\echo BONUS DONE
