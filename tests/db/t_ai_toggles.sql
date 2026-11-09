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
begin;
alter table profiles disable trigger all;
insert into auth.users(id,email) values ('00000000-0000-0000-0000-0000000000d1','mgr@staff.x') on conflict do nothing;
insert into profiles(id,full_name,role) values ('00000000-0000-0000-0000-0000000000d1','المدير','manager') on conflict (id) do nothing;
alter table profiles enable trigger all;
delete from app_settings where key in ('assistant_analytics_enabled','assistant_manager_enabled','assistant_enabled');
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('افتراضي: المالك mode=owner والتحليل شغّال', (select ai_mode()='owner' and ai_admin_ok()));
select t.ok('افتراضي: تحليل شغّال فعلًا', (select (ai_overview(now()-interval '1 day', now())->>'revenue') is not null));
reset role;
-- قفل التحليل (قيمة boolean زي ما الإعدادات بتحفظها)
insert into app_settings(key,value) values ('assistant_analytics_enabled','false'::jsonb) on conflict (key) do update set value='false'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('التحليل مقفول: المالك mode=manager (تشغيل بس)', (select ai_mode()='manager' and not ai_admin_ok() and ai_mgr_ok()));
select t.fl('التحليل مقفول: ai_overview مرفوض حتى للمالك', $$select ai_overview(now()-interval '1 day', now())$$);
select t.fl('التحليل مقفول: ai_invoices مرفوض', $$select ai_invoices(now()-interval '1 day', now())$$);
select t.ok('التحليل مقفول: أدوات التشغيل شغّالة', (select ai_find_staff('أحمد') is not null));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('المدير مش متأثر: mode=manager', (select ai_mode()='manager'));
reset role;
-- إعادة التفعيل (نص ومنطقي)
insert into app_settings(key,value) values ('assistant_analytics_enabled','true'::jsonb) on conflict (key) do update set value='true'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('تفعيل boolean true: رجع owner', (select ai_mode()='owner'));
reset role;
insert into app_settings(key,value) values ('assistant_analytics_enabled','"false"'::jsonb) on conflict (key) do update set value='"false"'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('القيمة النصية "false" كمان بتقفل', (select ai_mode()='manager'));
reset role;
delete from app_settings where key='assistant_analytics_enabled';
-- مفتاح المدير + المفتاح العام
insert into app_settings(key,value) values ('assistant_manager_enabled','false'::jsonb) on conflict (key) do update set value='false'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000d1');
select t.ok('مساعد المدير مقفول (boolean)', (select ai_mode() is null));
reset role;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المالك مش بيتأثر بقفل المدير', (select ai_mode()='owner'));
select t.ok('assistant_hit شغّال', (select (assistant_hit()->>'ok')::boolean));
reset role;
insert into app_settings(key,value) values ('assistant_enabled','false'::jsonb) on conflict (key) do update set value='false'::jsonb;
select t.as_('00000000-0000-0000-0000-0000000000a1');
select t.ok('المفتاح العام boolean false بيوقف الكل', (select not (assistant_hit()->>'ok')::boolean and assistant_hit()->>'reason'='off'));
reset role;
rollback;
\echo TOGGLES DONE
