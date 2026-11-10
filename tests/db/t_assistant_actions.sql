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
\i sql/patch_ai_toggles.sql
\i sql/patch_assistant_actions.sql
begin;
alter table profiles disable trigger all;
insert into auth.users(id,email) values ('00000000-0000-0000-0000-0000000000d1','mgr@staff.x') on conflict do nothing;
insert into profiles(id,full_name,role) values ('00000000-0000-0000-0000-0000000000d1','المدير','manager') on conflict (id) do nothing;
alter table profiles enable trigger all;
delete from assistant_usage; delete from app_settings where key like 'assistant_%';
-- بدون حد يومي للإدارة
select t.as_('00000000-0000-0000-0000-0000000000a1');
do $$ declare r jsonb; i int; begin for i in 1..130 loop r := assistant_hit(); if not (r->>'ok')::boolean then raise exception 'FAIL: owner blocked at %', i; end if; end loop;
  if r->>'left' is not null or r->>'role' <> 'owner' then raise exception 'FAIL: shape %', r; end if; raise notice 'PASS: المالك 130 سؤال من غير حد'; end $$;
reset role;
select t.as_('00000000-0000-0000-0000-0000000000d1');
do $$ declare r jsonb; i int; begin for i in 1..100 loop r := assistant_hit(); if not (r->>'ok')::boolean then raise exception 'FAIL: manager blocked at %', i; end if; end loop; raise notice 'PASS: المدير 100 سؤال من غير حد'; end $$;
reset role;
select t.ok('العداد بيتسجل للإحصاء', (select n = 130 from assistant_usage where user_id = '00000000-0000-0000-0000-0000000000a1'));
-- العميل والموظف لسه بحدودهم
insert into app_settings(key,value) values ('assistant_limit_staff','3'::jsonb),('assistant_limit_customer','2'::jsonb);
select t.as_('00000000-0000-0000-0000-0000000000b1');
do $$ declare r jsonb; i int; begin for i in 1..3 loop r := assistant_hit(); end loop; r := assistant_hit(); if (r->>'ok')::boolean or r->>'reason' <> 'limit' then raise exception 'FAIL: barber limit %', r; end if; raise notice 'PASS: الحلاق لسه بحده (3)'; end $$;
reset role;
select t.as_('00000000-0000-0000-0000-0000000000c1');
do $$ declare r jsonb; i int; begin for i in 1..2 loop r := assistant_hit(); end loop; r := assistant_hit(); if (r->>'ok')::boolean or r->>'reason' <> 'limit' then raise exception 'FAIL: customer limit %', r; end if; raise notice 'PASS: العميل لسه بحده (2)'; end $$;
reset role;
-- المفتاح العام لسه بيوقف الكل بما فيهم المالك
insert into app_settings(key,value) values ('assistant_enabled','false'::jsonb);
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('assistant_enabled=false بيوقف المالك كمان', (select assistant_hit()->>'reason' = 'off'));
reset role;
delete from app_settings where key = 'assistant_enabled';
-- سجل العمليات
select t.as_('00000000-0000-0000-0000-0000000000d1');
select assistant_log_action('staff_tx', '{"staff_id":"x","amount":50,"password":"123456","pw":"abc"}'::jsonb, 'done', '{"ok":true}'::jsonb) as lid \gset
select t.ok('المدير يسجّل عملية', (:lid) > 0);
select t.fl('حالة غلط', $$select assistant_log_action('x','{}','weird')$$);
select t.fl('المدير مايقدرش يكتب في الجدول مباشرة', $$insert into assistant_actions(user_id,action,status) values (auth.uid(),'x','done')$$);
select t.ok('المدير مايقراش السجل (للمالك بس)', (select count(*) = 0 from assistant_actions));
reset role;
select t.ok('كلمة السر مابتتسجلش أبدًا', (select not (params ? 'password') and not (params ? 'pw') and (params->>'amount')::int = 50 from assistant_actions where id = :lid));
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك يقرا السجل', (select count(*) = 1 from assistant_actions));
select t.fl('المالك مايعدّلش السجل', $$update assistant_actions set status='failed'$$);
select t.fl('المالك مايمسحش السجل', $$delete from assistant_actions$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a2');
select t.fl('الكاشير مايسجّلش', $$select assistant_log_action('x','{}','done')$$);
select t.ok('الكاشير مايقراش السجل', (select count(*) = 0 from assistant_actions));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000c1');
select t.fl('العميل مايسجّلش', $$select assistant_log_action('x','{}','done')$$);
reset role;
-- إشعار عميل
select t.as_('00000000-0000-0000-0000-0000000000d1');
select ai_notify_customer(1, 'عرض النهارده', 'خصم 10% على القصة') as nid \gset
select t.ok('المدير يبعت رسالة لعميل', (:nid) > 0);
select t.fl('عنوان فاضي', $$select ai_notify_customer(1, '  ', 'x')$$);
select t.fl('عنوان طويل', $$select ai_notify_customer(1, repeat('ع', 81), 'x')$$);
select t.fl('رسالة طويلة', $$select ai_notify_customer(1, 'x', repeat('ع', 301))$$);
select t.fl('عميل مش موجود', $$select ai_notify_customer(99999, 'x', 'y')$$);
reset role;
select t.ok('الرسالة اتسجلت للعميل بنوع staff_message', (select title = 'عرض النهارده' and kind = 'staff_message' and customer_id = 1 from customer_notifications where id = :nid));
select t.as_('00000000-0000-0000-0000-0000000000b1');
select t.fl('الحلاق مايبعتش رسايل', $$select ai_notify_customer(1, 'x', 'y')$$);
reset role;
select t.as_('00000000-0000-0000-0000-0000000000c1');
select t.fl('العميل مايبعتش رسايل', $$select ai_notify_customer(1, 'x', 'y')$$);
reset role;
select t.ok('anon مالوش execute', not has_function_privilege('anon','ai_notify_customer(bigint,text,text)','execute') and not has_function_privilege('anon','assistant_log_action(text,jsonb,text,jsonb,text)','execute'));
rollback;
\echo ACTIONS DONE
